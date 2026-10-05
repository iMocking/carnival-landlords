# 狂欢斗地主服务端镜像。
#
# ## 为什么构建上下文必须是仓库根目录
#
# 因为 go.mod / go.sum 在根上、模块名是 carnival-landlords，服务端代码
# （cmd/ internal/ configs/）也都在根上：
#		docker build -f Dockerfile -t carnival-landlords-server .
#
# 注意这里**不能**把上下文缩到某个子目录（例如 `docker build .` 换成
# `docker build ./cmd`），否则 go.mod 找不到、依赖没法解析。
#
# ## 为什么根目录一定要有 .dockerignore
#
# 构建上下文是**整个仓库**，其中 apps/ 下还有前端工程（website / admin）。
# 那些目录里可能有 node_modules、构建产物、设计稿原图，
# 没有任何一个参与服务端编译，却会被逐字节打包发给 Docker daemon。
# 少了根目录的 .dockerignore，每次 build 都要白等几分钟上传这些文件，
# 镜像层也白白变胖。排除清单见仓库根目录的 .dockerignore。

# ---------------- 构建阶段 ----------------
FROM golang:1.26-alpine AS builder

# git：go mod 通过 VCS 拉取依赖时需要；
# ca-certificates：模块代理（goproxy.cn）走 HTTPS；
# tzdata：编译期用不到，但和运行阶段装的是同一份证书包来源，装在这里便于统一说明。
RUN apk add --no-cache git ca-certificates tzdata

# 依赖代理。国内构建默认走 goproxy.cn，海外 CI 可传
# --build-arg GOPROXY=https://proxy.golang.org,direct 覆盖。
ARG GOPROXY=https://goproxy.cn,direct
ENV GOPROXY=${GOPROXY}
# 关闭校验库求和：校验和已经记录在 go.sum 里，容器内再查一次 sum.golang.org
# 只会带来额外的外网依赖与失败面。
ENV GOSUMDB=off

WORKDIR /src

# 先只拷依赖清单再 download：只要 go.mod/go.sum 没变，这一层就能命中缓存，
# 改一行业务代码不会重新拉全部依赖。
COPY go.mod go.sum ./
RUN go mod download

# 再拷整个仓库：模块根就是仓库根，cmd/ internal/ configs/ 都在这一层。
COPY . .

# VERSION 由 CI 传入，写进 main.version。
# 注意：cmd/api 与 cmd/migrate 必须各自声明 `var version = "dev"`，
# 否则 -X main.version=... 会静默不生效（go build 不会为不存在的符号报错）。
ARG VERSION=dev
ARG TARGETOS=linux
ARG TARGETARCH=amd64

# CGO_ENABLED=0：产出静态二进制，于是运行阶段可以用 alpine（甚至 scratch）而不必带 libc；
# -trimpath：编译路径不进二进制，避免把构建机的目录结构泄露到线上；
# -s -w：去掉符号表与 DWARF 调试信息，镜像更小。
ENV CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH}
RUN mkdir -p /out \
	&& go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/api     ./cmd/api \
	&& go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/migrate ./cmd/migrate

# ---------------- 运行阶段 ----------------
# 固定到 3.21 而不是 alpine:latest：latest 会在某次不经意的重建后
# 悄悄换成新的大版本，从而把"镜像今天能跑、明天跑不起来"变成常态。
FROM alpine:3.21

# tzdata 不能省：服务端的"当天"是**服务器本地时区**的自然日
# （daily_stats.date 存 'YYYY-MM-DD'，签到与每日任务都按它切天）。
# 镜像里没有 tzdata 时容器只会是 UTC，跨零点的那几个小时的日常与签到
# 会全部错位。这里连同 ca-certificates 一起从构建阶段拷过来，都不用 apk。
#
# 注意：装了 tzdata 只是"能识别时区"，还得通过 TZ 环境变量**选定时区**。
# 只装不设的结果仍然是 UTC（见 docker-compose.yml 里 api 服务的 TZ）。
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# 非 root 运行：容器被攻破时不该顺手拿到宿主机上的写权限。
# 固定 uid/gid 10001 是为了让 K8s 的 runAsUser / 目录属主在各环境里保持一致。
RUN addgroup -g 10001 -S app \
	&& adduser -u 10001 -S -G app -h /app app

WORKDIR /app

# 二进制 + 配置文件一起进镜像，并 chown 给运行用户。
# 配置走 configs/config.yaml（config.Load 的 CONFIG_FILE 默认值），
# 其中每个字段都能被 CL_* 环境变量覆盖 —— 生产密钥/口令一律走环境变量注入，
# 不要把真实的 jwt.secret 或数据库口令写进这份文件。
COPY --from=builder --chown=10001:10001 /out/api     /app/api
COPY --from=builder --chown=10001:10001 /out/migrate /app/migrate
COPY --chown=10001:10001 configs /app/configs

USER 10001:10001

# 迁移工具随镜像一起发布：生产环境靠 `docker run --rm <镜像> /app/migrate`
# 建表，而不是把 postgres.auto_migrate 打开（config.Validate 也禁止生产开启）。
EXPOSE 8080

# 探针打 127.0.0.1 而不是 localhost：容器里 localhost 可能先解析到 ::1，
# 而 http.addr 默认是 ":8080"（IPv4/IPv6 双栈）—— 用字面 IPv4 最不容易出意外。
# 用 wget --spider 而不是 wget -qO-：只发 HEAD 请求，不会把响应体打进容器日志。
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
	CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1

# 只启动 api。需要执行迁移时用同一镜像覆盖入口：
#		docker run --rm --env-file .env <镜像> /app/migrate
ENTRYPOINT ["/app/api"]
