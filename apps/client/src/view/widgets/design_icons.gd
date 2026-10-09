class_name DesignIcons
extends RefCounted
## 新视觉稿（`apps/client/design_update/`）里的小图标，几何 1:1 抄自设计稿的 SVG path。
##
## 与 `DecoIcons`（手搓近似图形）的分工：这里每个常量的字符串都是导出稿里
## `<path d="...">` 的原文，配色也照抄同子树 `<use fill>` 上的颜色，所以改稿时
## 只替换常量即可，图形不会"看着差不多但就是不一样"。
##
## 每个图标都有 `static func` 工厂，返回可直接放进 `HBoxContainer` / `VBoxContainer`
## 的 `Control`：`custom_minimum_size` 是 `size × size` 的正方形，内部按设计稿比例
## **等比缩放并居中**，因此同一个图标画在任意尺寸都清晰，也不会被拉扁。
##
## 坐标约定（与导出稿一致，`_path()` 靠这个保证不缩放错）：
##   设计稿坐标 = `viewBox` 坐标 + 该 `<svg>` 图层的 `translate`
## 常量注释里的"画布"是该图标所有部件的并集包围盒（px），工厂把它等比塞进 `size`。
## 之所以传 `translate` 而不是矩形：导出稿的 `viewBox` 为了容纳描边会留白
## （例如宝箱高光 p34 的 `viewBox` 高 12.52，实际几何只有 7.85），
## 用包围盒去 fit 会把图形放大错。
##
## 多部件图标用 `_icon()` + `draw` 回调自己组合：有 path 的用 path，
## 圆 / 椭圆 / 圆角矩形用程序化多边形——设计稿里这些部件本身就是 CSS
## `background-color` + `border-radius`，导出稿里没有对应的 `<path>`。

## 小于这个边长就不画：布局首帧控件尺寸为 0 是常态，
## 退化多边形会让 RenderingServer 报「Invalid polygon data, triangulation failed」。
const MIN_DRAW := 6.0

## 圆 / 椭圆的细分数。设计稿里最大的圆直径 62px，40 段肉眼看不出折线。
const ELLIPSE_SEGMENTS := 40

## ---------------------------------------------------------------- 几何常量
## 全部是设计稿 `<path d="...">` 原文，请勿手改。

## 信封封盖（登录界面 #p8，25.2×11.05，填充 #7A4A12）
const ENVELOPE_FLAP := "M12 7.75L0.6 -0.8L-0.6 0.8L11.4 9.8L12 10.25L24.6 0.8L23.4 -0.8L12 7.75Z"

## 挂锁锁梁（登录界面 #p11，14.5×10.25，填充 #F2C14E）
const LOCK_SHACKLE := "M-1.25 6L-1.25 9L1.25 9L1.25 6Q1.25 4.03249 2.64124 2.64124Q4.03249 1.25 6 1.25Q7.96751 1.25 9.35876 2.64124Q10.75 4.03249 10.75 6L10.75 9L13.25 9L13.25 6Q13.25 2.99696 11.1265 0.873475Q9.00305 -1.25 6 -1.25Q2.99695 -1.25 0.873476 0.873476Q-1.25 2.99695 -1.25 6Z"

## 眼睛轮廓（登录界面 #p12，26.3324×16，填充 #C8A05A）
## 两条子路径：外层杏仁形 + 内层杏仁形，绕向相反，是**孔**（`_path()` 会缝成镂空环）
const EYE := "M12 -1Q15.8383 -1 19.0414 0.747104Q22.5689 2.67124 24.8575 6.4855L25.1662 7L24.8575 7.5145Q22.5689 11.3288 19.0414 13.2529Q15.8383 15 12 15Q8.16167 15 4.95865 13.2529Q1.43106 11.3288 -0.857493 7.5145L-1.16619 7L-0.857493 6.4855Q1.43107 2.67124 4.95865 0.747104Q8.16167 -1 12 -1ZM12 1Q8.67166 1 5.91635 2.5029Q3.10531 4.03619 1.1788 7Q3.10531 9.96381 5.91635 11.4971Q8.67166 13 12 13Q15.3283 13 18.0836 11.4971Q20.8947 9.96381 22.8212 7Q20.8947 4.03619 18.0836 2.5029Q15.3283 1 12 1Z"

## 对勾（登录界面 #p5，12.5643×10.0643，填充 #F2C14E）
const CHECK := "M3.43461 5.66685L0.883883 3.11612Q0.524014 2.73492 0 2.75Q-0.524014 2.73492 -0.883883 3.11612Q-1.26508 3.47599 -1.25 4Q-1.26508 4.52401 -0.883883 4.88388L2.61612 8.38388Q2.97599 8.76508 3.5 8.75Q4.02401 8.76508 4.38388 8.38388Q4.39964 8.36812 4.41483 8.35181Q4.43002 8.3355 4.44461 8.31866L10.9446 0.818663Q11.2992 0.432549 11.2468 -0.0890588Q11.2246 -0.612816 10.8187 -0.944611Q10.4325 -1.2992 9.91094 -1.24682Q9.38718 -1.22453 9.05539 -0.818663L3.43461 5.66685Z"

## 房子 / 基础设置（系统设置 #p8，20×20.5，填充 #7A4A12）
## 注意：这张稿子把"设置"做成房子（左侧页签的"基础设置"），不是齿轮
const HOME := "M0 9L10 0L20 9L20 19C20 19.4142 19.8536 19.7678 19.5607 20.0607C19.2678 20.3536 18.9142 20.5 18.5 20.5L13 20.5L13 13.5L7 13.5L7 20.5L1.5 20.5C1.08579 20.5 0.732233 20.3536 0.43934 20.0607C0.146446 19.7678 0 19.4142 0 19L0 9Z"

## 音符 / 音效设置（系统设置 #p11，17.122×19.8021，填充 #E8C87A）
## 这张稿子里音效图标是**双八分音符**，没有喇叭开关图形
const MUSIC := "M4.98051 1.99916L16.9712 0L16.9712 14.4939C16.9598 15.5598 16.5474 16.4373 15.7342 17.1262C14.9209 17.8151 13.9879 18.0773 12.935 17.913C11.8821 17.7486 11.0732 17.2145 10.5084 16.3105C9.94365 15.4065 9.81811 14.4451 10.1318 13.4264C10.4455 12.4076 11.0901 11.6835 12.0654 11.2541C13.0408 10.8247 14.0099 10.8384 14.9728 11.2952L14.9728 4.4981L6.97896 5.99747L6.97896 16.4931C6.88034 17.5336 6.41 18.3634 5.56794 18.9822C4.72588 19.6011 3.79377 19.8021 2.77163 19.5852C1.74948 19.3683 0.979201 18.8061 0.460791 17.8986C-0.0576183 16.991 -0.150748 16.0418 0.181402 15.0507C0.513552 14.0597 1.15988 13.3584 2.12037 12.9469C3.08087 12.5353 4.03425 12.5512 4.98051 12.9945L4.98051 1.99916Z"

## 盾牌 / 隐私设置（系统设置 #p15，18×22，填充 #E8C87A）
const SHIELD := "M9 0L18 3L18 10C18 16 14 20 9 22C4 20 0 16 0 10L0 3L9 0Z"

## 小人下半身 / 账号设置（系统设置 #p13，18×9，填充 #E8C87A）
const ACCOUNT_BODY := "M0 9C0 6.51472 0.878679 4.3934 2.63604 2.63604C4.3934 0.87868 6.51472 9.53674e-07 9 0C11.4853 9.53674e-07 13.6066 0.87868 15.364 2.63604C17.1213 4.3934 18 6.51472 18 9L0 9Z"

## 小挂锁锁梁（系统设置 #p35，10×7，填充 #E8C87A）
const LOCK_SHACKLE_SMALL := "M-1 4L-1 6L1 6L1 4Q1 2.75736 1.87868 1.87868Q2.75736 1 4 1Q5.24264 1 6.12132 1.87868Q7 2.75736 7 4L7 6L9 6L9 4Q9 1.92893 7.53553 0.464466Q6.07106 -1 4 -1Q1.92893 -1 0.464465 0.464466Q-1 1.92893 -1 4Z"

## 登出（门框，系统设置 #p36，7.5121×16.0241，填充 #E8C87A）
const LOGOUT_DOOR := "M1.5 1L5.5 1Q5.91921 1.01207 6.20711 0.707107Q6.51207 0.419211 6.5 0Q6.51207 -0.419211 6.20711 -0.707107Q5.91921 -1.01207 5.5 -1L1.5 -1Q0.464466 -1 -0.267767 -0.267767Q-1 0.464466 -1 1.5L-1 12.5Q-1 13.5355 -0.267768 14.2678Q0.464469 15 1.5 15L5.5 15Q5.91921 15.0121 6.20711 14.7071Q6.51207 14.4192 6.5 14Q6.51207 13.5808 6.20711 13.2929Q5.91921 12.9879 5.5 13L1.5 13Q1.29289 13 1.14645 12.8536Q1 12.7071 1 12.5L1 1.5Q1 1.29289 1.14645 1.14645Q1.29289 1 1.5 1Z"

## 登出（外推箭头，系统设置 #p37，10.0241×10.0241，填充 #E8C87A）
const LOGOUT_ARROW := "M4.70711 -0.707107L8.70711 3.29289Q9.01207 3.58079 9 4Q9.01207 4.41921 8.70711 4.70711L4.70711 8.70711Q4.41921 9.01206 4 9Q3.58079 9.01206 3.29289 8.70711Q2.98793 8.41921 3 8Q2.98793 7.58079 3.29289 7.29289L5.58579 5L0 5Q-0.419211 5.01207 -0.707107 4.70711Q-1.01207 4.41921 -1 4Q-1.01207 3.58079 -0.707107 3.29289Q-0.419211 2.98793 0 3L5.58579 3L3.29289 0.707107Q2.98793 0.419211 3 0Q2.98793 -0.419211 3.29289 -0.707107Q3.58079 -1.01207 4 -1Q4.41921 -1.01207 4.70711 -0.707107Z"

## 齿轮 / 设置（对局牌桌 #p12，16×16.5，填充 #E8D5A8）
## 两条子路径绕向相同（中心圆 + 齿盘），是**两个独立实心块**不是孔
const GEAR := "M6.8 12C5.8335 12 5.00854 11.6583 4.32513 10.9749C3.64171 10.2915 3.3 9.4665 3.3 8.5C3.3 7.5335 3.64171 6.70854 4.32513 6.02513C5.00854 5.34171 5.8335 5 6.8 5C7.7665 5 8.59146 5.34171 9.27487 6.02513C9.95829 6.70854 10.3 7.5335 10.3 8.5C10.3 9.4665 9.95829 10.2915 9.27487 10.9749C8.59146 11.6583 7.7665 12 6.8 12ZM14.2 9.4L16 10.8L14.2 13.9L12 13.2C11.7142 13.4322 11.412 13.6405 11.0934 13.825C10.7748 14.0094 10.4436 14.1678 10.1 14.3L9.8 16.5L6.2 16.5L5.9 14.3C5.55637 14.1678 5.22524 14.0094 4.90661 13.825C4.58797 13.6405 4.28577 13.4322 4 13.2L1.8 13.9L0 10.8L1.8 9.4C1.74519 9.03538 1.71779 8.66871 1.71779 8.3C1.71779 7.93128 1.74519 7.56462 1.8 7.2L0 5.8L1.8 2.7L4 3.4C4.28577 3.16784 4.58797 2.95952 4.90661 2.77505C5.22524 2.59057 5.55638 2.43222 5.9 2.3L6.2 0L9.8 0L10.1 2.3C10.4436 2.43222 10.7748 2.59057 11.0934 2.77505C11.412 2.95952 11.7142 3.16784 12 3.4L14.2 2.7L16 5.8L14.2 7.2C14.35 7.92 14.35 8.66 14.2 9.4Z"

## 小人下半身 / 头像占位（对局牌桌 #p15，34.6667×13，填充 #E8D5A8）
const USER_BODY := "M0 13C0 4.33333 7.8 0 17.3333 0C26.8667 0 34.6667 4.33333 34.6667 13L0 13Z"

## 关闭叉号（对局牌桌 #p53，21.0603×21.0603，填充 #FFFFFF）
const CLOSE := "M11.5355 8L17.7678 1.76777Q18.5302 1.04803 18.5 0Q18.5302 -1.04803 17.7678 -1.76777Q17.048 -2.53017 16 -2.5Q14.952 -2.53017 14.2322 -1.76777L8 4.46447L1.76777 -1.76777Q1.04803 -2.53017 0 -2.5Q-1.04803 -2.53017 -1.76777 -1.76777Q-2.53017 -1.04803 -2.5 0Q-2.53017 1.04803 -1.76777 1.76777L4.46447 8L-1.76777 14.2322Q-2.53017 14.952 -2.5 16Q-2.53017 17.048 -1.76777 17.7678Q-1.04803 18.5302 0 18.5Q1.04803 18.5302 1.76777 17.7678L8 11.5355L14.2322 17.7678Q14.952 18.5302 16 18.5Q17.048 18.5302 17.7678 17.7678Q18.5302 17.048 18.5 16Q18.5302 14.952 17.7678 14.2322L11.5355 8Z"

## 金币上的五角星（个人中心 #p10，16×16.63，填充 #E8961E）
const COIN_STAR := "M8 0L10 6.26326L16 6.47923L11.2 10.3668L12.9 16.63L8 12.9585L3.1 16.63L4.8 10.3668L0 6.47924L6 6.26326L8 0Z"

## 钻石顶面（个人中心 #p11，30×30.2364，填充 #45B7F0）
const GEM_TOP := "M15 30.2364L0 8.63898L7 0L23 0L30 8.63898L15 30.2364Z"

## 钻石左刻面（个人中心 #p12，15×21.5974，填充 #7FD4F8）
const GEM_LEFT := "M15 21.5974L0 0L15 0L15 21.5974Z"

## 钻石右刻面（个人中心 #p13，15×21.5974，填充 #2B96D8）
const GEM_RIGHT := "M0 21.5974L15 0L0 0L0 21.5974Z"

## 钻石腰线高光（个人中心 #p14，30×1，填充 #BFE9FC）
const GEM_SHINE := "M30 -0.5L0 -0.5L0 0.5L30 0.5L30 -0.5Z"

## 奖杯杯身（个人中心 #p15，18×22.2274，填充 #FFD75E）
const TROPHY_CUP := "M0 0L18 0L18 9.11892C18 17.098 14 22.2274 9 22.2274C4 22.2274 0 17.098 0 9.11892L0 0Z"

## 奖杯双耳（个人中心 #p16，32.8×14.621，填充 #E8961E）
## 两条子路径是左右两只耳朵，同向，是**两个独立实心块**
const TROPHY_HANDLES := "M6 1.4L1.43418 1.4Q1.62586 5.18627 2.89232 7.41581Q4.27963 9.85811 7.10474 10.4882L6.49526 13.221Q-1.4 11.4602 -1.4 0L-1.4 -1.4L6 -1.4L6 1.4ZM30 -1.4L24 -1.4L24 1.4L28.5658 1.4Q28.3741 5.18626 27.1077 7.41581Q25.7204 9.85811 22.8953 10.4882L23.5047 13.221Q31.4 11.4602 31.4 0L31.4 -1.4L30 -1.4Z"

## 奖杯底座弧（个人中心 #p17，14×6.1553，填充 #FFD75E）
const TROPHY_BASE := "M0 6.15527C0 2.27973 3 0 7 0C11 0 14 2.27973 14 6.15527L0 6.15527Z"

## 成就绶带（个人中心 #p46，12×13，填充 #E8453A）
const RIBBON := "M0 0L12 0L9 13L3 13L0 0Z"

## 奖牌上的五角星（个人中心 #p47，11.6×10.6，填充 #E8961E）
const MEDAL_STAR := "M5.8 0L7.6 3.6L11.6 4L8.6 6.7L9.5 10.6L5.8 8.6L2.1 10.6L3 6.7L0 4L4 3.6L5.8 0Z"

## 信封封盖（个人中心 信封图标 #p51，31.1827×13.0465，填充 #C8A05A）
const MAIL_FLAP := "M15 9.75993L0.591364 -0.806405L-0.591364 0.806405L14.4086 11.8064L15 12.2401L30.5914 0.806405L29.4086 -0.806405L15 9.75993Z"

## 右箭头 ›（个人中心 #p38，12.9072×19.3239，填充 #FFF3C4）
const CHEVRON_RIGHT := "M9.74482 5.65166L1.49482 -1.68167Q0.80788 -2.32861 -0.132124 -2.24612Q-1.07532 -2.21783 -1.68167 -1.49482Q-2.32861 -0.80788 -2.24612 0.132124Q-2.21783 1.07532 -1.49482 1.68167L4.8633 7.33333L-1.49482 12.985Q-2.21783 13.5913 -2.24612 14.5345Q-2.32861 15.4745 -1.68167 16.1615Q-1.07532 16.8845 -0.132124 16.9128Q0.80788 16.9953 1.49482 16.3483L9.74482 9.01501Q9.79424 8.97108 9.84099 8.92432Q9.88774 8.87757 9.93167 8.82815Q10.5786 8.14121 10.4961 7.20121Q10.4678 6.25802 9.74482 5.65166Z"

## 返回箭头 ‹（个人中心 #p60，20.1613×32.1613，填充 #F5C242）
## 每个页面顶栏的返回键都是同一条几何，只是 id 不同（系统设置 #p46、商城 #p82……）
const BACK_ARROW := "M4.40884 13L16.0414 2.19838Q16.9876 1.36915 16.9979 0.111035Q17.0807 -1.1444 16.1984 -2.04135Q15.3691 -2.98757 14.111 -2.99794Q12.8556 -3.08066 11.9586 -2.19838L-2.04135 10.8016Q-2.98757 11.6309 -2.99794 12.889Q-3.08066 14.1444 -2.19838 15.0414Q-2.16059 15.0821 -2.12132 15.1213Q-2.08205 15.1606 -2.04135 15.1984L11.9586 28.1984Q12.8556 29.0807 14.111 28.9979Q15.3691 28.9876 16.1984 28.0414Q17.0807 27.1444 16.9979 25.889Q16.9876 24.6309 16.0414 23.8016L4.40884 13Z"

## 调色板（个人中心 皮肤图标 #p42，30×27，填充 #F5C64B）
const PALETTE := "M15 0C6.7 0 0 6 0 13.5C0 21 6.7 27 15 27C16.4 27 17.5 25.9 17.5 24.5C17.5 23.9 17.3 23.3 16.9 22.8C16.5 22.3 16.3 21.6 16.3 20.9C16.3 19.2 17.7 17.8 19.4 17.8L23 17.8C26.9 17.8 30 14.9 30 11.2C30 4.9 23.3 0 15 0Z"

## 奖牌上的五角星（我的成就 奖牌图标 #p26，19.6×17.7，填充 #E8961E）
const MEDAL_STAR_LARGE := "M9.8 0L12.8 6.2L19.6 6.7L14.4 11.1L16.1 17.7L9.8 14L3.5 17.7L5.2 11.1L0 6.7L6.8 6.2L9.8 0Z"

## 宝箱锁扣横缝（我的成就 宝箱图标 #p32，20×2，填充 #7A4A12）
const CHEST_CLASP := "M20 -1L0 -1L0 1L20 1L20 -1Z"

## 奖励五角星（活动中心 奖励图标 #p12，18.4×17.8，填充 #E8961E）
const STAR := "M9.2 0L11.4 6.6L18.4 6.9L12.9 11.1L14.8 17.8L9.2 13.9L3.6 17.8L5.5 11.1L0 6.9L7 6.6L9.2 0Z"

## 红包封口（活动中心 红包图标 #p42，33.8×8.7，填充 #FFD75E）
const RED_PACKET_FLAP := "M16 4.5Q8.5 4.5 0.9 -1.2L-0.9 1.2Q7.5 7.5 16 7.5Q24.5 7.5 32.9 1.2L31.1 -1.2Q23.5 4.5 16 4.5Z"

## 加号（活动中心 红包图标 #p43，6×6，填充 #C42B1E）
## 原稿里是红包封口上的装饰十字，也是全稿唯一的"加号"几何
const PLUS := "M4 2L4 0L2 0L2 2L0 2L0 4L2 4L2 6L4 6L4 4L6 4L6 2L4 2Z"

## 宝箱盖（活动中心 宝箱图标 #p48，44×18.6667，填充 #F7B93C）
const CHEST_LID := "M0 8C14.6667 -2.66667 29.3333 -2.66667 44 8L44 16L0 16L0 8Z"

## 宝箱盖高光（活动中心 宝箱图标 #p49，37.2141×12.5226，填充 #FFDD77）
const CHEST_GLOSS := "M36.6071 3.9073Q18 -6.42994 -0.607054 3.9073L0.607054 6.0927Q18 -3.57005 35.3929 6.0927L36.6071 3.9073Z"

## 任务旗杆（活动中心 任务图标 #p54，3×30，填充 #F5C242）
const FLAG_POLE := "M1.5 30L1.5 0L-1.5 0L-1.5 30L1.5 30Z"

## 任务旗面（活动中心 任务图标 #p55，18×12，填充 #E84B35）
const FLAG := "M0 0L18 0L14 6L18 12L0 12L0 0Z"

## 任务旗面褶（活动中心 任务图标 #p56，14×12，填充 #F56B4E）
const FLAG_FOLD := "M0 0L0 12L14 12L10.5 6L14 0L0 0Z"

## 喇叭（消息中心 喇叭 #p11，11.6667×18.6667，填充 #4A2600）
const SPEAKER := "M0 5.83333L0 12.8333L4.66667 12.8333L11.6667 18.6667L11.6667 0L4.66667 5.83333L0 5.83333Z"

## 喇叭声波（消息中心 喇叭 #p12，3.6837×10.1991，填充 #4A2600）
const SPEAKER_WAVE := "M2.6675 4.08333Q2.6675 1.29282 0.714143 -0.7Q0.429311 -1.00782 0.0100001 -0.99995Q-0.40907 -1.01621 -0.7 -0.714143Q-1.00782 -0.429311 -0.99995 -0.0100001Q-1.01621 0.40907 -0.714143 0.7Q0.6675 2.10956 0.6675 4.08333Q0.667499 6.05711 -0.714142 7.46667Q-1.01621 7.7576 -0.99995 8.17667Q-1.00782 8.59598 -0.700001 8.88081Q-0.40907 9.18287 0.00999944 9.16662Q0.429311 9.17449 0.714142 8.86667Q2.6675 6.87385 2.6675 4.08333Z"

## 好友申请小人下半身（消息中心 好友 #p17，18.6667×7，填充 #F7D98C）
const FRIEND_BODY_SMALL := "M0 7C0 2.33333 4.2 0 9.33333 0C14.4667 0 18.6667 2.33333 18.6667 7L0 7Z"

## 礼盒蝴蝶结（消息中心 礼物 #p22，17.079×19.3732，填充 #4A2600）
const GIFT_RIBBON := "M6.15256 18.2446L6.15256 3.32328Q5.48358 2.09958 4.41225 1.48414Q3.43096 0.92042 2.4306 1.01136Q1.58915 1.08786 1.2095 1.56655Q0.852776 2.01633 1.10125 2.76174L-0.79612 3.3942Q-1.38694 1.62175 -0.357497 0.323762Q0.554657 -0.826345 2.24953 -0.980424Q3.87925 -1.12858 5.4085 -0.250074Q6.40854 0.324417 7.15256 1.23503Q7.89659 0.324417 8.89663 -0.250074Q10.4259 -1.12858 12.0556 -0.980424Q13.7505 -0.826345 14.6626 0.323762Q15.6921 1.62175 15.1012 3.3942L13.2039 2.76174Q13.4523 2.01633 13.0956 1.56655Q12.716 1.08786 11.8745 1.01136Q10.8742 0.92042 9.89287 1.48414Q8.82154 2.09958 8.15256 3.32328L8.15256 18.2446L6.15256 18.2446Z"

## 刷新 / 版本更新（消息中心 更新 #p27，22.2123×22.5838，填充 #F7D98C）
const REFRESH := "M19.8135 4.65725L19.8135 0Q19.828 -0.503054 19.462 -0.848528Q19.1165 -1.21448 18.6135 -1.2Q18.1104 -1.21448 17.765 -0.848528Q17.399 -0.503054 17.4135 0L17.4135 3.45725L16.948 3.45725Q17.1454 3.17409 17.1378 2.80403Q17.1563 2.30111 16.7932 1.9527Q13.1503 -1.74943 7.99879 -1.10262Q2.84747 -0.455844 0.231391 4.03187Q-2.38434 8.519 -0.412337 13.3244Q1.55988 18.1303 6.57259 19.4823Q11.5857 20.8344 15.7042 17.6707Q19.8222 14.5075 19.8135 9.31249Q19.8271 8.80941 19.4606 8.46455Q19.1145 8.09917 18.6115 8.11449Q18.1084 8.10085 17.7635 8.46738Q17.3982 8.81347 17.4135 9.3165Q17.4202 13.3263 14.2422 15.7674Q11.0648 18.2082 7.19757 17.1651Q3.32993 16.122 1.80798 12.4133Q0.285812 8.70403 2.30481 5.24056Q4.32347 1.77768 8.29778 1.27868Q12.1452 0.795619 14.902 3.45725L13.9601 3.45725Q13.4571 3.44277 13.1116 3.80872Q12.7456 4.15419 12.7601 4.65725Q12.7456 5.1603 13.1116 5.50577Q13.4571 5.87173 13.9601 5.85725L18.6135 5.85725Q19.1165 5.87173 19.462 5.50577Q19.828 5.1603 19.8135 4.65725Z"

## 金币上的五角星（狂欢斗地主游戏大厅 金币图标 #p19，19.6×18.8，填充 #E8961E）
const COIN_STAR_LARGE := "M9.8 0L12.2 7L19.6 7.3L13.8 11.7L15.8 18.8L9.8 14.6L3.8 18.8L5.8 11.7L0 7.3L7.4 7L9.8 0Z"

## 金币左上高光（狂欢斗地主游戏大厅 金币图标 #p20，10.7313×9.7313，填充 #FFF3C4）
const COIN_GLINT := "M2.53599 1.82684Q0.296678 3.78624 -1.10306 6.41198Q-1.36287 6.8673 -1.19577 7.36419Q-1.05753 7.86986 -0.588019 8.10306Q-0.1327 8.36287 0.364187 8.19577Q0.869862 8.05753 1.10306 7.58802Q2.28745 5.36624 4.18225 3.70828Q6.07705 2.05033 8.43639 1.17135Q8.9327 1.00254 9.13685 0.519695Q9.36842 0.0493865 9.17135 -0.436392Q9.00254 -0.932701 8.51969 -1.13685Q8.04939 -1.36842 7.56361 -1.17135Q4.7753 -0.132555 2.53599 1.82684Z"

## 灯笼灯身云纹（狂欢斗地主游戏大厅 灯笼图标 #p28，30.6087×26.5216，填充 #FFE08A）
## 三条子路径是同向的三道装饰线，是**三个独立实心块**不是孔
const LANTERN_BODY := "M28.0534 2.1886Q15.3044 -3.69559 2.55527 2.1886L3.18386 3.55053Q15.3044 -2.04354 27.4248 3.55053L28.0534 2.1886ZM30.6087 8.81522L0 8.81522L0 10.3152L30.6087 10.3152L30.6087 8.81522ZM27.4248 15.5799Q15.3044 21.174 3.18386 15.5799L2.55527 16.9418Q15.3044 22.826 28.0534 16.9418L27.4248 15.5799Z"

## 灯笼左骨架（狂欢斗地主游戏大厅 灯笼图标 #p29，2.9085×20.1818，填充 #C86A12）
const LANTERN_CORD_LEFT := "M0.497748 20.1344L2.41079 0.0474046L1.4153 -0.0474046L-0.497748 20.0396L0.497748 20.1344Z"

## 灯笼右骨架（狂欢斗地主游戏大厅 灯笼图标 #p30，2.9085×20.1818，填充 #C86A12）
const LANTERN_CORD_RIGHT := "M2.41079 20.0396L0.497748 -0.0474046L-0.497748 0.0474046L1.4153 20.1344L2.41079 20.0396Z"

## 灯笼提梁（狂欢斗地主游戏大厅 灯笼图标 #p27，2×4.7826，填充 #F5C242）
const LANTERN_HOOK := "M1 4.78261L1 0L-1 0L-1 4.78261L1 4.78261Z"

## 灯笼流苏（狂欢斗地主游戏大厅 灯笼图标 #p31，2.5×6.2174，填充 #E8453A）
const LANTERN_TASSEL := "M1.25 6.21739L1.25 0L-1.25 0L-1.25 6.21739L1.25 6.21739Z"

## 宝箱盖（狂欢斗地主游戏大厅 宝箱图标 #p33，46×18.3333，填充 #F7B93C）
const CHEST_LID_LARGE := "M0 8.5C15.3333 -2.83333 30.6667 -2.83333 46 8.5L46 15.5L0 15.5L0 8.5Z"

## 宝箱盖高光（狂欢斗地主游戏大厅 宝箱图标 #p34，39.2526×13.5262，填充 #FFDD77）
const CHEST_GLOSS_LARGE := "M38.6263 4.41822Q19 -6.94438 -0.626295 4.41822L0.626295 6.58178Q19 -4.05563 37.3737 6.58178L38.6263 4.41822Z"

## 时钟指针（狂欢斗地主游戏大厅 快速开始图标 #p44，13.2181×20.7181，填充 #C86A0C）
## "快速开始"圆钮就是这只钟：外圈金环 + 米白表盘 + 这根指针
const CLOCK_HANDS := "M2.25 9.71312L2.25 0Q2.27715 -0.943226 1.59099 -1.59099Q0.943226 -2.27715 0 -2.25Q-0.943226 -2.27715 -1.59099 -1.59099Q-2.27715 -0.943226 -2.25 0L-2.25 12.2869L7.3592 17.9394Q8.15844 18.441 9.06466 18.178Q9.98452 17.9676 10.4394 17.1408Q10.941 16.3416 10.678 15.4353Q10.4676 14.5155 9.64079 14.0606L2.25 9.71312Z"

## 奖杯杯身（狂欢斗地主游戏大厅 奖杯图标 #p60，24×25，填充 #FFD75E）
const TROPHY_CUP_LARGE := "M0 0L24 0L24 10C24 19 19 25 12 25C5 25 0 19 0 10L0 0Z"

## 奖杯双耳（狂欢斗地主游戏大厅 奖杯图标 #p61，43.5×16.9762，填充 #E8961E）
const TROPHY_HANDLES_LARGE := "M8 1.75L1.80415 1.75Q2.07545 5.95831 3.70609 8.40427Q5.53554 11.1485 9.2877 11.7738L8.7123 15.2262Q3.46446 14.3516 0.793912 10.3457Q-1.75 6.52986 -1.75 0L-1.75 -1.75L8 -1.75L8 1.75ZM40 -1.75L32 -1.75L32 1.75L38.1959 1.75Q37.9246 5.95831 36.2939 8.40427Q34.4645 11.1485 30.7123 11.7738L31.2877 15.2262Q36.5355 14.3516 39.2061 10.3457Q41.75 6.52986 41.75 0L41.75 -1.75L40 -1.75Z"

## 奖杯底座弧（狂欢斗地主游戏大厅 奖杯图标 #p62，20×7，填充 #FFD75E）
const TROPHY_BASE_LARGE := "M0 7C0 2.5 4 0 10 0C16 0 20 2.5 20 7L0 7Z"

## 好友小人下半身（狂欢斗地主游戏大厅 好友图标 #p68，30×15，填充 #FFF6DE / #FFD75E 各画一次）
const FRIEND_BODY := "M0 15C0 5.5 6.8 0 15 0C23.2 0 30 5.5 30 15L0 15Z"

## 奖杯杯身高光（狂欢斗地主游戏大厅 奖杯图标 #p63，12×7，填充 #FFF6DE）
## 两条子路径是两根同向的横线（独立实心块），个人中心的奖杯没有这两笔
const TROPHY_GLOSS := "M12 -1L0 -1L0 1L12 1L12 -1ZM12 4L0 4L0 6L12 6L12 4Z"

## 四角星光芒（狂欢斗地主游戏大厅 星芒高光1 #p36，24×24，填充 #FFFDF2）
const SPARKLE := "M12 0L14.6 9.4L24 12L14.6 14.6L12 24L9.4 14.6L0 12L9.4 9.4L12 0Z"

## 金币上的五角星（商城 金币图标 #p76，12.8×12.3，填充 #E8961E）
const COIN_STAR_SMALL := "M6.4 0L8 4.6L12.8 4.8L9 7.7L10.3 12.3L6.4 9.6L2.5 12.3L3.8 7.7L0 4.8L4.8 4.6L6.4 0Z"

## 钻石顶面（商城 钻石图标 #p78，22×20.5，填充 #45B7F0）
const GEM_TOP_SMALL := "M11 20.5L0 6L5.8 0L16.2 0L22 6L11 20.5Z"

## 钻石左刻面（商城 钻石图标 #p79，11×14.5，填充 #7FD4F8）
const GEM_LEFT_SMALL := "M11 14.5L0 0L11 0L11 14.5Z"

## 钻石右刻面（商城 钻石图标 #p80，11×14.5，填充 #2B96D8）
const GEM_RIGHT_SMALL := "M0 14.5L11 0L0 0L0 14.5Z"

## 钻石腰线高光（商城 钻石图标 #p81，22×1，填充 #BFE9FC）
const GEM_SHINE_SMALL := "M22 -0.5L0 -0.5L0 0.5L22 0.5L22 -0.5Z"

## 其它页面出现但这里没做成图标的形态，记录一下避免以后重复找：
##   * `签到`：每日签到面板是卡片网格 + 宝箱，稿子里**没有日历图标**；
##   * `音效开关`：只有"音乐开关/音效开关"两个 toggle 圆钮（CSS 圆角矩形），
##     没有 `sound_on` / `sound_off` 喇叭图形，音效页签用的是音符 `MUSIC`；
##   * `减号`：全稿唯一的十字几何是红包封口上的 `PLUS`，没有减号。

## ---------------------------------------------------------------- 绘制工具

## 造一个多部件图标控件。
## `canvas` 是设计稿里该图标所有部件的并集包围盒（px），等比缩放后居中放进控件正方形。
## `painter` 收到 `(ci, s, o)`：`s` 是设计稿 px → 屏幕 px 的缩放，`o` 是居中平移量。
static func _icon(canvas: Rect2, size: float, painter: Callable) -> Control:
    var control := Control.new()
    control.name = "DesignIcon"
    control.custom_minimum_size = Vector2(size, size)
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    control.resized.connect(control.queue_redraw)
    control.draw.connect(func() -> void:
        var side := minf(control.size.x, control.size.y)
        if side < MIN_DRAW:
            return
        var scale := side / maxf(canvas.size.x, canvas.size.y)
        var origin := (Vector2(side, side) - canvas.size * scale) * 0.5 - canvas.position * scale
        painter.call(control, scale, origin))
    return control


## 画一条设计稿 path。
## `at` 是导出稿里该 `<svg>` 图层的 `translate`（px）：设计稿坐标 = `viewBox` 坐标 + `at`，
## 所以几何与设计稿严格 1:1，也不会被 `viewBox` 的描边留白放大错。
##
## 为什么不用 `SvgPath.draw_paths()`：它按"首条子路径当外轮廓、其余布尔减"处理，
## 但 Godot 的 `Geometry2D.clip_polygons()` 会把"孔"作为**反向绕行**的独立多边形返回，
## `SvgPath._fill()` 随后把每一块都当实心填充 —— 实测眼睛（常量 `EYE`）会糊成实心杏仁。
## 这里自己分辨"实心块 / 孔"：孔用 keyhole 缝法缝进宿主外轮廓后一次性填充，
## 其余子路径各自当独立实心块（齿轮的中心圆、奖杯的左右耳、灯笼的三道云纹）。
static func _path(ci: CanvasItem, d: String, at: Vector2, color: Color, s: float, o: Vector2) -> void:
    var shapes: Array = []
    var shape_holes: Array = []
    for sub: PackedVector2Array in SvgPath.cached(d):
        var moved := _moved(sub, at, s, o)
        if moved.size() < 3:
            continue
        var host := _hole_host(moved, shapes)
        if host >= 0:
            shape_holes[host].append(moved)
        else:
            shapes.append(moved)
            shape_holes.append([])
    for i in shapes.size():
        var outline: PackedVector2Array = shapes[i]
        for hole: PackedVector2Array in shape_holes[i]:
            outline = _sew_hole(outline, hole)
        ci.draw_colored_polygon(outline, color)


## 这条子路径是某个已有实心块的"孔"吗？是则返回宿主下标，否则 -1。
## 判据要同时满足，缺一不可：
##   1. 绕向与宿主相反（设计工具导出孔时会反向绕行）；
##   2. 首顶点落在宿主内部。
## 只看绕向会误判奖杯的左右耳（两条子路径绕向相反但互不相交，缝起来会自交、
## 三角化直接失败）；只看包含会误判齿轮的中心圆（圆在齿盘内部但同向，是实体）。
static func _hole_host(sub: PackedVector2Array, shapes: Array) -> int:
    var sub_sign := signf(_signed_area(sub))
    for i in shapes.size():
        var base: PackedVector2Array = shapes[i]
        if sub_sign == signf(_signed_area(base)):
            continue
        if Geometry2D.is_point_in_polygon(sub[0], base):
            return i
    return -1


## 把一条子路径从 `viewBox` 坐标搬到屏幕坐标
static func _moved(sub: PackedVector2Array, at: Vector2, s: float, o: Vector2) -> PackedVector2Array:
    var moved := PackedVector2Array()
    for point in sub:
        moved.append((point + at) * s + o)
    return moved


## 多边形的有符号面积（鞋带公式；正负即绕向）
static func _signed_area(points: PackedVector2Array) -> float:
    var sum := 0.0
    for i in points.size():
        var a := points[i]
        var b := points[(i + 1) % points.size()]
        sum += a.x * b.y - b.x * a.y
    return sum * 0.5


## keyhole 缝法：绕外轮廓一圈 → 从最近的一对顶点切进孔 → 沿孔**原绕向**走一圈 → 切回来。
## 缝出来的是一条简单多边形（中间有一道零宽缝），`draw_colored_polygon()` 三角化后
## 得到的就是真正的"有洞"图形。孔的顶点顺序必须保持原样，反过来会把孔补实。
static func _sew_hole(outer: PackedVector2Array, hole: PackedVector2Array) -> PackedVector2Array:
    if outer.size() < 3 or hole.size() < 3:
        return outer
    var best_index := 0
    var best_distance := INF
    for i in outer.size():
        var distance := outer[i].distance_squared_to(hole[0])
        if distance < best_distance:
            best_distance = distance
            best_index = i
    var out := PackedVector2Array()
    for step in outer.size() + 1:
        out.append(outer[(best_index + step) % outer.size()])
    out.append(hole[0])
    for step in range(1, hole.size()):
        out.append(hole[step])
    out.append(hole[0])
    return out


## 圆 / 椭圆（设计稿里 `border-radius: 50%` 的部件）。
## 注意稿子里的金币是 34×36.72 的**椭圆**不是正圆（设计工具整体缩放过），所以不能用 draw_circle。
static func _disc(ci: CanvasItem, box: Rect2, color: Color, s: float, o: Vector2) -> void:
    var rect := Rect2(box.position * s + o, box.size * s)
    if rect.size.x < 1.0 or rect.size.y < 1.0:
        return
    ci.draw_colored_polygon(_ellipse_points(rect), color)


## 椭圆描边环（金币 / 奖牌 / 时钟的圈）
static func _ring(ci: CanvasItem, box: Rect2, width: float, color: Color, s: float, o: Vector2) -> void:
    var rect := Rect2(box.position * s + o, box.size * s)
    if rect.size.x < 2.0 or rect.size.y < 2.0:
        return
    var points := _ellipse_points(rect)
    points.append(points[0])
    ci.draw_polyline(points, color, maxf(width * s, 0.6), true)


## 圆角矩形（设计稿里 `border-radius` 是 px 的部件，例如输入框底板、礼盒盒身）
static func _rounded(ci: CanvasItem, box: Rect2, radius: float, color: Color, s: float, o: Vector2) -> void:
    var rect := Rect2(box.position * s + o, box.size * s)
    if rect.size.x < 1.5 or rect.size.y < 1.5:
        return
    var r := clampf(radius * s, 0.0, minf(rect.size.x, rect.size.y) * 0.5 - 0.5)
    ci.draw_colored_polygon(GlossyBox.rounded_rect_points(rect, r, r, r, r), color)


## 圆角矩形描边（复制图标的两张纸、消息中心的信封边框）
static func _outline(ci: CanvasItem, box: Rect2, radius: float, width: float, color: Color,
        s: float, o: Vector2) -> void:
    var rect := Rect2(box.position * s + o, box.size * s)
    if rect.size.x < 2.0 or rect.size.y < 2.0:
        return
    var r := clampf(radius * s, 0.0, minf(rect.size.x, rect.size.y) * 0.5 - 0.5)
    var points := GlossyBox.rounded_rect_points(rect, r, r, r, r)
    points.append(points[0])
    ci.draw_polyline(points, color, maxf(width * s, 0.6), true)


## 椭圆采样点（不闭合，交给调用方决定填充还是描边）
static func _ellipse_points(box: Rect2, segments: int = ELLIPSE_SEGMENTS) -> PackedVector2Array:
    var points := PackedVector2Array()
    var center := box.get_center()
    var radius := box.size * 0.5
    for i in segments:
        var angle := TAU * float(i) / float(segments)
        points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
    return points


## ---------------------------------------------------------------- 图标

## 信封 / 邮箱输入框（登录界面 信封图标，画布 26×20）
static func envelope(color: Color = Color("#f2c14e"), size: float = 22.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 26.0, 20.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _rounded(ci, Rect2(0.0, 0.0, 26.0, 20.0), 3.0, color, s, o)
            _path(ci, ENVELOPE_FLAP, Vector2(1.0, 2.0), Color("#7a4a12"), s, o))


## 挂锁 / 密码输入框、修改密码行（登录界面 锁图标，画布 18×23.25）
static func lock(color: Color = Color("#f2c14e"), size: float = 24.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 18.0, 23.25), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, LOCK_SHACKLE, Vector2(3.0, 1.25), color, s, o)
            _rounded(ci, Rect2(0.0, 10.25, 18.0, 13.0), 3.0, color, s, o)
            _disc(ci, Rect2(7.0, 14.25, 4.0, 4.0), Color("#7a4a12"), s, o))


## 小挂锁（系统设置 锁图标，画布 12×16）
static func lock_small(color: Color = Color("#e8c87a"), size: float = 20.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 12.0, 16.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, LOCK_SHACKLE_SMALL, Vector2(2.0, 1.0), color, s, o)
            _rounded(ci, Rect2(0.0, 7.0, 12.0, 9.0), 2.0, color, s, o))


## 眼睛 / 密码显隐（登录界面 眼睛图标，画布 26.3324×16）
static func eye(color: Color = Color("#c8a05a"), size: float = 26.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 26.3324, 16.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, EYE, Vector2(1.1662, 1.0), color, s, o)
            _disc(ci, Rect2(10.1662, 5.0, 6.0, 6.0), color, s, o))


## 对勾（登录界面 对勾，画布 12.5643×10.0643）
static func check(color: Color = Color("#f2c14e"), size: float = 13.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 12.5643, 10.0643), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, CHECK, Vector2(1.2651, 1.2992), color, s, o))


## 圆形勾选框"记住账号"（登录界面 勾选框，画布 22×22，含 2px 描边）
static func checkbox(size: float = 18.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 22.0, 22.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(2.0, 2.0, 18.0, 18.0), Color("#c97b1e"), s, o)
            _path(ci, CHECK, Vector2(6.0, 7.0), Color("#f2c14e"), s, o)
            _ring(ci, Rect2(2.0, 2.0, 18.0, 18.0), 2.0, Color("#f7d98c"), s, o))


## 齿轮 / 对局内设置按钮（对局牌桌 齿轮，画布 16×16.5）
static func gear(color: Color = Color("#e8d5a8"), size: float = 20.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 16.0, 16.5), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, GEAR, Vector2.ZERO, color, s, o))


## 房子 / 基础设置页签（系统设置 基础图标，画布 20×20.5）
## 新稿把"设置"画成房子；齿轮另有 `gear()`（对局内设置按钮）
static func home(color: Color = Color("#7a4a12"), size: float = 21.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 20.0, 20.5), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, HOME, Vector2.ZERO, color, s, o))


## 音符 / 音效设置（系统设置 音效图标，画布 17.122×19.8021）
static func music(color: Color = Color("#e8c87a"), size: float = 20.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 17.122, 19.8021), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, MUSIC, Vector2(0.1507, 0.0), color, s, o))


## 盾牌 / 隐私设置（系统设置 隐私图标，画布 18×22）
static func shield(color: Color = Color("#e8c87a"), size: float = 22.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 18.0, 22.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, SHIELD, Vector2.ZERO, color, s, o))


## 手机 / 绑定手机（系统设置 手机图标，画布 10×17）
static func phone(color: Color = Color("#e8c87a"), size: float = 17.0,
        screen: Color = Color("#7a2e12")) -> Control:
    return _icon(Rect2(0.0, 0.0, 10.0, 17.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _rounded(ci, Rect2(0.0, 0.0, 10.0, 17.0), 2.5, color, s, o)
            _rounded(ci, Rect2(2.0, 2.5, 6.0, 10.0), 1.0, screen, s, o))


## 登出 / 退出登录（系统设置 登出图标，画布 15.512×16.0241）
static func logout(color: Color = Color("#e8c87a"), size: float = 16.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 15.512, 16.0241), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, LOGOUT_DOOR, Vector2(1.0, 1.0121), color, s, o)
            _path(ci, LOGOUT_ARROW, Vector2(6.5, 4.0121), color, s, o))


## 小人 / 账号设置页签、好友申请（系统设置 账号图标，画布 18×19.5）
static func account(color: Color = Color("#e8c87a"), size: float = 20.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 18.0, 19.5), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(4.5, 0.0, 9.0, 9.0), color, s, o)
            _path(ci, ACCOUNT_BODY, Vector2(0.0, 10.5), color, s, o))


## 头像占位 / 座位小人（对局牌桌 人像，画布 34.6667×34.66）
static func user(color: Color = Color("#e8d5a8"), size: float = 35.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 34.6667, 34.66), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(8.66, 0.0, 17.33, 17.33), color, s, o)
            _path(ci, USER_BODY, Vector2(0.0, 21.66), color, s, o))


## 右箭头 ›（个人中心 右箭头，画布 12.9072×19.3239）
static func chevron_right(color: Color = Color("#fff3c4"), size: float = 13.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 12.9072, 19.3239), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, CHEVRON_RIGHT, Vector2(2.3286, 2.3286), color, s, o))


## 返回箭头 ‹（个人中心 返回箭头，画布 20.1613×32.1613）
##
## 默认**纯白**（按需求）：原先金顶栏上用 `#f5c242`（琥珀）、深色浮层顶栏上用 `#7a4408`（深棕），
## 两种都不醒目 —— 前者与金色顶栏几乎同色，后者在暗红顶栏上基本看不见。
## 顶栏标题是暖白描边字，箭头跟着用白色才在同一条视觉语言里。
static func back_arrow(color: Color = Color.WHITE, size: float = 32.0) -> Control:
    var icon := _icon(Rect2(0.0, 0.0, 20.1613, 32.1613), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, BACK_ARROW, Vector2(3.0807, 3.0807), color, s, o))
    # 图标是即时绘制的，颜色只活在闭包里、节点上取不到，
    # 所以挂一份到 meta 上当测试探针（`ui_refactor_test` 断言这一枚是白色）。
    icon.set_meta("icon_color", color)
    return icon


## 关闭叉号 ✕（对局牌桌 关闭按钮里的叉号，画布 21.0603×21.0603；
## 按钮底板的红色圆角方块是另一个部件，不在这里，需要的话用 GlossyBox 自己画）
static func close(color: Color = Color("#ffffff"), size: float = 21.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 21.0603, 21.0603), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, CLOSE, Vector2(2.5302, 2.5302), color, s, o))


## 五角星 / 积分（活动中心 奖励图标，画布 18.4×17.8）
static func star(color: Color = Color("#e8961e"), size: float = 18.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 18.4, 17.8), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, STAR, Vector2.ZERO, color, s, o))


## 四角星光芒（狂欢斗地主游戏大厅 星芒高光，画布 24×24）
static func sparkle(color: Color = Color("#fffdf2"), size: float = 24.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 24.0, 24.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, SPARKLE, Vector2.ZERO, color, s, o))


## 加号（活动中心 红包图标封口上的十字，画布 6×6）
static func plus(color: Color = Color("#c42b1e"), size: float = 8.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 6.0, 6.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, PLUS, Vector2.ZERO, color, s, o))


## 减号（画布 6×2）。
## 设计稿里**没有**减号：全稿唯一的十字几何是红包封口上的 `PLUS`。
## 这里取那条 path 的横杠（y 2~4 那一段）作为最接近的几何，改稿时请一并替换。
static func minus(color: Color = Color("#c42b1e"), size: float = 8.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 6.0, 2.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _rounded(ci, Rect2(0.0, 0.0, 6.0, 2.0), 0.0, color, s, o))


## 喇叭 / 系统通知（消息中心 喇叭，画布 18.4175×18.6667）
static func speaker(color: Color = Color("#4a2600"), size: float = 19.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 18.4175, 18.6667), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, SPEAKER, Vector2.ZERO, color, s, o)
            _path(ci, SPEAKER_WAVE, Vector2(15.75, 5.25), color, s, o))


## 刷新 / 版本更新（消息中心 更新，画布 22.2123×22.5838）
static func refresh(color: Color = Color("#f7d98c"), size: float = 23.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 22.2123, 22.5838), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, REFRESH, Vector2(2.3843, 1.7494), color, s, o))


## 复制 / 复制 ID（个人中心 复制图标，画布 22×25）
static func copy(color: Color = Color("#e8c88a"), size: float = 25.0,
        paper: Color = Color("#5e140f")) -> Control:
    return _icon(Rect2(0.0, 0.0, 22.0, 25.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _outline(ci, Rect2(6.0, 2.0, 14.0, 17.0), 3.0, 2.0, color, s, o)
            _rounded(ci, Rect2(2.0, 6.0, 14.0, 17.0), 3.0, paper, s, o)
            _outline(ci, Rect2(2.0, 6.0, 14.0, 17.0), 3.0, 2.0, color, s, o))


## 任务旗 / 每日任务（活动中心 任务图标，画布 21.5×30）
static func flag(size: float = 30.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 21.5, 30.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, FLAG_POLE, Vector2(1.5, 0.0), Color("#f5c242"), s, o)
            _path(ci, FLAG, Vector2(3.5, 2.0), Color("#e84b35"), s, o)
            _path(ci, FLAG_FOLD, Vector2(3.5, 2.0), Color("#f56b4e"), s, o))


## 金币（个人中心 金币图标，画布 34×36.72）。
## 稿子里的金币是椭圆 + 内椭圆 + 描边环 + 五角星，商城 / 成就 / 活动中心 / 大厅
## 用的是同一套形状（只是整体缩放不同，并且大厅多一道左上高光），所以这里只保留一套几何。
static func coin(size: float = 35.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 34.0, 36.72), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(0.0, 0.0, 34.0, 36.72), Color("#e8961e"), s, o)
            _disc(ci, Rect2(3.0, 3.24, 28.0, 30.24), Color("#ffd75e"), s, o)
            _ring(ci, Rect2(3.0, 3.24, 28.0, 30.2364), 1.5, Color("#d98e12"), s, o)
            _path(ci, COIN_STAR, Vector2(9.0, 8.64), Color("#e8961e"), s, o))


## 带高光的金币（狂欢斗地主游戏大厅 金币图标，画布 42×42；顶部资源条用这个）
static func coin_glossy(size: float = 35.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 42.0, 42.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(0.0, 0.0, 42.0, 42.0), Color("#e8961e"), s, o)
            _disc(ci, Rect2(3.5, 3.5, 35.0, 35.0), Color("#ffd75e"), s, o)
            _ring(ci, Rect2(3.5, 3.5, 35.0, 35.0), 1.6, Color("#d98e12"), s, o)
            _path(ci, COIN_STAR_LARGE, Vector2(11.2, 11.0), Color("#e8961e"), s, o)
            _path(ci, COIN_GLINT, Vector2(8.0, 5.0), Color("#fff3c4"), s, o))


## 小金币（商城 金币图标，画布 27×27）
static func coin_small(size: float = 27.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 27.0, 27.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(0.0, 0.0, 27.0, 27.0), Color("#e8961e"), s, o)
            _disc(ci, Rect2(2.5, 2.5, 22.0, 22.0), Color("#ffd75e"), s, o)
            _ring(ci, Rect2(2.5, 2.5, 22.0, 22.0), 1.2, Color("#d98e12"), s, o)
            _path(ci, COIN_STAR_SMALL, Vector2(7.1, 6.5), Color("#e8961e"), s, o))


## 钻石 / 充值货币（个人中心 钻石图标，画布 30×30.2364）
static func gem(size: float = 30.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 30.0, 30.2374), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, GEM_TOP, Vector2.ZERO, Color("#45b7f0"), s, o)
            _path(ci, GEM_LEFT, Vector2(0.0, 8.64), Color("#7fd4f8"), s, o)
            _path(ci, GEM_RIGHT, Vector2(15.0, 8.64), Color("#2b96d8"), s, o)
            _path(ci, GEM_SHINE, Vector2(0.0, 8.64), Color("#bfe9fc"), s, o))


## 小钻石（商城 钻石图标，画布 22×20.5）
static func gem_small(size: float = 22.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 22.0, 20.5), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, GEM_TOP_SMALL, Vector2.ZERO, Color("#45b7f0"), s, o)
            _path(ci, GEM_LEFT_SMALL, Vector2(0.0, 6.0), Color("#7fd4f8"), s, o)
            _path(ci, GEM_RIGHT_SMALL, Vector2(11.0, 6.0), Color("#2b96d8"), s, o)
            _path(ci, GEM_SHINE_SMALL, Vector2(0.0, 6.0), Color("#bfe9fc"), s, o))


## 奖杯 / 竞技分（个人中心 奖杯图标，画布 32.8×36.48）
## 大厅"挑战赛"的奖杯多了两道杯身高光，其余几何一致
static func trophy(size: float = 36.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 32.8, 36.48), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, TROPHY_CUP, Vector2(7.4, 0.0), Color("#ffd75e"), s, o)
            _path(ci, TROPHY_HANDLES, Vector2(1.4, 2.28), Color("#e8961e"), s, o)
            _rounded(ci, Rect2(14.4, 21.66, 4.6, 5.7), 0.0, Color("#e8961e"), s, o)
            _path(ci, TROPHY_BASE, Vector2(9.4, 26.9), Color("#ffd75e"), s, o)
            _rounded(ci, Rect2(7.4, 33.06, 18.0, 3.42), 1.5, Color("#e8961e"), s, o))


## 大号奖杯（狂欢斗地主游戏大厅 奖杯图标，画布 43.5×42）
static func trophy_large(size: float = 42.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 43.5, 42.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, TROPHY_CUP_LARGE, Vector2(9.75, 0.0), Color("#ffd75e"), s, o)
            _path(ci, TROPHY_HANDLES_LARGE, Vector2(1.75, 2.0), Color("#e8961e"), s, o)
            _rounded(ci, Rect2(18.75, 24.0, 6.0, 7.0), 0.0, Color("#e8961e"), s, o)
            _path(ci, TROPHY_BASE_LARGE, Vector2(11.75, 31.0), Color("#ffd75e"), s, o)
            _rounded(ci, Rect2(8.75, 38.0, 26.0, 4.0), 2.0, Color("#e8961e"), s, o)
            _path(ci, TROPHY_GLOSS, Vector2(15.75, 5.0), Color("#fff6de"), s, o))


## 宝箱 / 商城入口（狂欢斗地主游戏大厅 宝箱图标，画布 46×41.4444）
## 盖子 + 箱体 + 深色箱带 + 浅色锁扣 + 锁眼 + 顶部高光
static func chest(size: float = 46.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 46.0, 41.4444), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, CHEST_LID_LARGE, Vector2(0.0, 6.9444), Color("#f7b93c"), s, o)
            _rounded(ci, Rect2(0.0, 22.4444, 46.0, 19.0), 4.0, Color("#e8961e"), s, o)
            _rounded(ci, Rect2(0.0, 20.4444, 46.0, 5.0), 0.0, Color("#b36a0c"), s, o)
            _rounded(ci, Rect2(18.0, 18.4444, 10.0, 14.0), 2.0, Color("#ffe08a"), s, o)
            _disc(ci, Rect2(20.4, 21.8444, 5.2, 5.2), Color("#7a3b00"), s, o)
            _path(ci, CHEST_GLOSS_LARGE, Vector2(4.0, 6.9444), Color("#ffdd77"), s, o))


## 小号宝箱 / 活动奖励（活动中心 宝箱图标，画布 44×40.4299）
static func chest_small(size: float = 44.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 44.0, 40.4299), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, CHEST_LID, Vector2(0.0, 6.4299), Color("#f7b93c"), s, o)
            _rounded(ci, Rect2(0.0, 22.4299, 44.0, 18.0), 4.0, Color("#e8961e"), s, o)
            _rounded(ci, Rect2(0.0, 20.4299, 44.0, 5.0), 0.0, Color("#b36a0c"), s, o)
            _rounded(ci, Rect2(17.0, 18.4299, 10.0, 13.0), 2.0, Color("#ffe08a"), s, o)
            _path(ci, CHEST_GLOSS, Vector2(4.0, 6.4299), Color("#ffdd77"), s, o))


## 奖励宝箱 / 成就领取（我的成就 宝箱图标，画布 40×40）
## 与 `chest()` 不是同一张图：这个是"深红包箱 + 金描边 + 金锁扣"
static func reward_chest(size: float = 40.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 40.0, 40.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _rounded(ci, Rect2(2.0, 2.0, 36.0, 36.0), 8.0, Color("#5a1608"), s, o)
            _outline(ci, Rect2(2.0, 2.0, 36.0, 36.0), 8.0, 2.0, Color("#e8b84b"), s, o)
            _rounded(ci, Rect2(10.0, 14.0, 20.0, 16.0), 2.0, Color("#f2c14e"), s, o)
            _path(ci, CHEST_CLASP, Vector2(10.0, 18.0), Color("#7a4a12"), s, o)
            _rounded(ci, Rect2(17.0, 15.0, 6.0, 6.0), 1.0, Color("#7a4a12"), s, o))


## 灯笼 / 活动中心入口（狂欢斗地主游戏大厅 灯笼图标，画布 30.61×41.61）
static func lantern(size: float = 42.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 30.61, 41.61), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, LANTERN_HOOK, Vector2(15.3, 0.0), Color("#f5c242"), s, o)
            _rounded(ci, Rect2(7.65, 3.83, 15.3, 3.83), 1.91, Color("#f5c242"), s, o)
            _disc(ci, Rect2(0.0, 6.22, 30.61, 23.91), Color("#f09a2e"), s, o)
            _path(ci, LANTERN_BODY, Vector2(0.0, 8.61), Color("#ffe08a"), s, o)
            _path(ci, LANTERN_CORD_LEFT, Vector2(7.65, 7.66), Color("#c86a12"), s, o)
            _path(ci, LANTERN_CORD_RIGHT, Vector2(21.04, 7.66), Color("#c86a12"), s, o)
            _rounded(ci, Rect2(9.56, 29.66, 11.48, 3.35), 1.67, Color("#f5c242"), s, o)
            _path(ci, LANTERN_TASSEL, Vector2(15.3, 33.0), Color("#e8453a"), s, o)
            _disc(ci, Rect2(13.87, 38.74, 2.87, 2.87), Color("#e8453a"), s, o))


## 两个小人 / 好友房（狂欢斗地主游戏大厅 好友图标，画布 52×37）
static func friends(size: float = 52.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 52.0, 37.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(6.0, 0.0, 18.0, 18.0), Color("#fff6de"), s, o)
            _path(ci, FRIEND_BODY, Vector2(0.0, 22.0), Color("#fff6de"), s, o)
            _disc(ci, Rect2(28.0, 0.0, 18.0, 18.0), Color("#ffd75e"), s, o)
            _path(ci, FRIEND_BODY, Vector2(22.0, 22.0), Color("#ffd75e"), s, o))


## 小人（消息中心 好友，画布 18.6667×18.66）
static func friend(color: Color = Color("#f7d98c"), size: float = 19.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 18.6667, 18.66), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(4.66, 0.0, 9.33, 9.33), color, s, o)
            _path(ci, FRIEND_BODY_SMALL, Vector2(0.0, 11.66), color, s, o))


## 奖牌（我的成就 奖牌图标，画布 40×40）
static func medal(size: float = 40.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 40.0, 40.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(0.0, 0.0, 40.0, 40.0), Color("#f5c242"), s, o)
            _disc(ci, Rect2(5.0, 5.0, 30.0, 30.0), Color("#ffde6e"), s, o)
            _ring(ci, Rect2(5.0, 5.0, 30.0, 30.0), 2.0, Color("#d98e12"), s, o)
            _path(ci, MEDAL_STAR_LARGE, Vector2(10.2, 9.0), Color("#e8961e"), s, o))


## 成就勋章 / 个人中心"我的成就"（个人中心 成就图标，画布 22×33）
## 与 `medal()` 不同：这个多一条红色绶带
static func achievement(size: float = 33.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 22.0, 33.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, RIBBON, Vector2(5.0, 0.0), Color("#e8453a"), s, o)
            _disc(ci, Rect2(0.0, 11.0, 22.0, 22.0), Color("#f5c242"), s, o)
            _disc(ci, Rect2(3.0, 14.0, 16.0, 16.0), Color("#ffe08a"), s, o)
            _path(ci, MEDAL_STAR, Vector2(5.2, 17.0), Color("#e8961e"), s, o))


## 红包（活动中心 红包图标，画布 48×50）
static func red_packet(size: float = 50.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 48.0, 50.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _rounded(ci, Rect2(8.0, 0.0, 32.0, 44.0), 6.0, Color("#e84b35"), s, o)
            _path(ci, RED_PACKET_FLAP, Vector2(8.0, 8.0), Color("#ffd75e"), s, o)
            _disc(ci, Rect2(17.0, 9.0, 14.0, 14.0), Color("#ffd75e"), s, o)
            _path(ci, PLUS, Vector2(21.0, 13.0), Color("#c42b1e"), s, o)
            _disc(ci, Rect2(0.0, 39.0, 20.0, 10.0), Color("#f5c242"), s, o)
            _disc(ci, Rect2(24.0, 40.0, 24.0, 10.0), Color("#ffd75e"), s, o))


## 礼盒 / 活动奖励消息（消息中心 礼物，画布 21×19.3786）
static func gift(color: Color = Color("#4a2600"), size: float = 21.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 21.0, 19.3786), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _rounded(ci, Rect2(1.17, 7.7086, 18.67, 11.67), 1.0, color, s, o)
            _rounded(ci, Rect2(0.0, 4.2086, 21.0, 4.67), 1.0, color, s, o)
            _path(ci, GIFT_RIBBON, Vector2(3.35, 1.1286), color, s, o))


## 消息 / "消息中心"菜单行（个人中心 信封图标，画布 33×25）
## 与 `envelope()` 不同：这个是米色信封 + 金描边 + 金色封盖，用在列表行
static func message(color: Color = Color("#f7efd8"), size: float = 33.0,
        flap: Color = Color("#c8a05a")) -> Control:
    return _icon(Rect2(0.0, 0.0, 33.0, 25.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _rounded(ci, Rect2(1.5, 1.5, 30.0, 22.0), 4.0, color, s, o)
            _path(ci, MAIL_FLAP, Vector2(1.5, 4.5), flap, s, o)
            _outline(ci, Rect2(1.5, 1.5, 30.0, 22.0), 4.0, 1.5, Color("#d9b97a"), s, o))


## 调色板 / 主题皮肤（个人中心 皮肤图标，画布 30×27）
static func palette(size: float = 30.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 30.0, 27.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _path(ci, PALETTE, Vector2.ZERO, Color("#f5c64b"), s, o)
            _disc(ci, Rect2(6.8, 5.8, 4.4, 4.4), Color("#7a2e12"), s, o)
            _disc(ci, Rect2(13.8, 3.3, 4.4, 4.4), Color("#7a2e12"), s, o)
            _disc(ci, Rect2(20.8, 5.8, 4.4, 4.4), Color("#7a2e12"), s, o)
            _disc(ci, Rect2(3.8, 11.8, 4.4, 4.4), Color("#e88b1a"), s, o))


## 时钟 / "快速开始"圆钮（狂欢斗地主游戏大厅 快速开始图标，画布 62×62）
static func clock(size: float = 62.0) -> Control:
    return _icon(Rect2(0.0, 0.0, 62.0, 62.0), size,
        func(ci: CanvasItem, s: float, o: Vector2) -> void:
            _disc(ci, Rect2(0.0, 0.0, 62.0, 62.0), Color("#e8961e"), s, o)
            _disc(ci, Rect2(4.0, 4.0, 54.0, 54.0), Color("#ffd75e"), s, o)
            _ring(ci, Rect2(4.0, 4.0, 54.0, 54.0), 2.0, Color("#d98e12"), s, o)
            _disc(ci, Rect2(11.0, 11.0, 40.0, 40.0), Color("#fff6de"), s, o)
            _ring(ci, Rect2(11.0, 11.0, 40.0, 40.0), 2.5, Color("#e8961e"), s, o)
            _path(ci, CLOCK_HANDS, Vector2(31.0, 20.0), Color("#c86a0c"), s, o))
