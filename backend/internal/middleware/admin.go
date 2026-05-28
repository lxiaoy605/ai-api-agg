package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// AdminAuth 管理员权限检查中间件（需在 JWTAuth 之后使用）
func AdminAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, _ := c.Get("role")
		if role != "admin" {
			c.JSON(http.StatusForbidden, gin.H{
				"code":    403,
				"message": "需要管理员权限",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}
