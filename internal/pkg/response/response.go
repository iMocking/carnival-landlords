// Package response 统一 HTTP 响应外壳。
//
// 所有接口都返回同一个信封结构，客户端只需要写一份解包逻辑：
//
//	{"code":0,"message":"ok","data":{...},"request_id":"..."}
//
// code == 0 表示成功；非 0 时 data 通常为空，message 可直接展示给玩家。
package response

import (
	"github.com/gin-gonic/gin"

	"carnival-landlords/internal/pkg/apperr"
)

// RequestIDKey 是请求 ID 在 gin.Context 中的键名，也是响应头名称。
const RequestIDKey = "X-Request-Id"

// Envelope 是统一响应体。
type Envelope struct {
	Code      int    `json:"code"`
	Message   string `json:"message"`
	Data      any    `json:"data,omitempty"`
	RequestID string `json:"request_id,omitempty"`
}

// Page 是统一分页结构。
type Page[T any] struct {
	Items    []T   `json:"items"`
	Total    int64 `json:"total"`
	Page     int   `json:"page"`
	PageSize int   `json:"page_size"`
}

// NewPage 构造分页结果，Items 为 nil 时替换成空数组，避免客户端拿到 null。
func NewPage[T any](items []T, total int64, page, pageSize int) Page[T] {
	if items == nil {
		items = []T{}
	}
	return Page[T]{Items: items, Total: total, Page: page, PageSize: pageSize}
}

func requestID(c *gin.Context) string {
	if v, ok := c.Get(RequestIDKey); ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return c.GetHeader(RequestIDKey)
}

// OK 返回成功响应。
func OK(c *gin.Context, data any) {
	c.JSON(200, Envelope{Code: int(apperr.CodeOK), Message: "ok", Data: data, RequestID: requestID(c)})
}

// Created 返回 201 + 成功信封（REST 语义需要时使用）。
func Created(c *gin.Context, data any) {
	c.JSON(201, Envelope{Code: int(apperr.CodeOK), Message: "ok", Data: data, RequestID: requestID(c)})
}

// Fail 返回失败响应。传 nil 时按内部错误处理。
func Fail(c *gin.Context, err error) {
	appErr := apperr.From(err)
	if appErr == nil {
		appErr = apperr.ErrInternal
	}
	status := appErr.Status
	if status == 0 {
		status = 500
	}
	c.AbortWithStatusJSON(status, Envelope{
		Code:      int(appErr.Code),
		Message:   appErr.Message,
		RequestID: requestID(c),
	})
}

// FailCode 直接按错误码返回。
func FailCode(c *gin.Context, code apperr.Code, message string) {
	appErr := apperr.New(code, 400, message)
	Fail(c, appErr)
}
