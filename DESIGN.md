# AiFlowHub — DESIGN.md

> **"Chinese AI Models. One Global API."**
>
> Design system v1.0 · Last updated 2026-05-29
> Target: aiflowhub.ai · Next.js + Tailwind CSS + shadcn/ui

---

## 1. Brand Identity

### 1.1 Brand Concept

AiFlowHub 是「中国模型出海的数字桥梁」——将 DeepSeek/GLM/Qwen/MiniMax/Moonshot
的能力汇成一条统一的全球 API。品牌视觉传达**连接、流动、亚洲 AI 网络**。

### 1.2 Logo Concept

- **图形**: 五角/六角网络节点图标，中心发光源向外辐射连接线
- **字标**: "AiFlowHub" 全小写，字体圆角几何感
- **变体**: 独立图形 + 字标横排 / 仅图形 / 仅字标
- **最小使用尺寸**: 图形 24×24px, 字标 120px 宽

### 1.3 Brand Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `brand.primary` | `#3B2FCE` | 主色，Logo、主按钮、标题强调 |
| `brand.secondary` | `#7B61FF` | 渐变终点、悬浮态、辅助点缀 |
| `brand.accent` | `#A78BFA` | 三级强调、标签、图标高亮 |
| `brand.glow` | `rgba(59,47,206,0.40)` | 辉光效果、卡片阴影 |

**渐变方向**: 左上→右下 (`135deg`), `#3B2FCE → #7B61FF`

### 1.4 Typography Stack

| Role | Font Stack |
|------|-----------|
| **Display / Headings** | `Inter Variable`, `Inter`, `SF Pro Display`, `system-ui`, sans-serif |
| **Body / UI** | `Inter Variable`, `Inter`, `SF Pro Text`, `system-ui`, sans-serif |
| **Mono / Code** | `JetBrains Mono`, `Fira Code`, `Cascadia Code`, `SF Mono`, `ui-monospace`, monospace |
| **CN Fallback** | `PingFang SC`, `Microsoft YaHei`, `Noto Sans SC` (append end of sans-serif stack) |

---

## 2. Typography

### 2.1 Type Scale

| Name | Size | Line-Height | Weight | Use |
|------|------|-------------|--------|-----|
| `text-xs` | 12px | 16px (1.333) | 400 | Captions, badges, chart labels |
| `text-sm` | 14px | 20px (1.428) | 400 | Body small, descriptions, form hints |
| `text-base` | 16px | 24px (1.5) | 400 | Body, inputs, list items |
| `text-lg` | 18px | 28px (1.555) | 500 | Lead paragraphs, card titles |
| `text-xl` | 20px | 28px (1.4) | 600 | Section headings, feature titles |
| `text-2xl` | 24px | 32px (1.333) | 600 | Page section headers, modal titles |
| `text-3xl` | 32px | 40px (1.25) | 700 | Hero sub-headlines |
| `text-4xl` | 40px | 48px (1.2) | 700 | Hero headlines |
| `text-5xl` | 56px | 64px (1.143) | 800 | Landing page hero (max) |

### 2.2 Font Weights

| Token | Value | Usage |
|-------|-------|-------|
| `fw-regular` | 400 | Body text, labels, inputs |
| `fw-medium` | 500 | Subtle emphasis, nav links, lead |
| `fw-semibold` | 600 | Headings, button text |
| `fw-bold` | 700 | Hero, strong emphasis |
| `fw-extrabold` | 800 | Landing hero only (sparingly) |

### 2.3 Letter Spacing

| Context | Value |
|---------|-------|
| Headings (xl+) | `-0.02em` |
| Body / UI | `-0.01em` |
| Mono / Code | `0` |
| All-caps badges | `+0.05em` |

---

## 3. Color Palette

### 3.1 Brand

| Swatch | Hex | CSS Variable |
|--------|-----|-------------|
| `brand.50` | `#F5F3FF` | `--brand-50` |
| `brand.100` | `#EDE9FE` | `--brand-100` |
| `brand.200` | `#DDD6FE` | `--brand-200` |
| `brand.300` | `#C4B5FD` | `--brand-300` |
| `brand.400` | `#A78BFA` | `--brand-400` |
| `brand.500` | `#7B61FF` | `--brand-500` (secondary) |
| `brand.600` | `#3B2FCE` | `--brand-600` (primary) |
| `brand.700` | `#2D22A3` | `--brand-700` |
| `brand.800` | `#1E1670` | `--brand-800` |
| `brand.900` | `#120D4A` | `--brand-900` |
| `brand.950` | `#0B0826` | `--brand-950` |

### 3.2 Neutrals

#### Dark Mode (default)

| Swatch | Hex | CSS Variable |
|--------|-----|-------------|
| `neutral.0` | `#FFFFFF` | `--neutral-0` |
| `neutral.50` | `#F8F8FC` | `--neutral-50` |
| `neutral.100` | `#EEEEF2` | `--neutral-100` |
| `neutral.200` | `#D4D4DC` | `--neutral-200` |
| `neutral.300` | `#A0A0B0` | `--neutral-300` |
| `neutral.400` | `#707088` | `--neutral-400` |
| `neutral.500` | `#4A4A5E` | `--neutral-500` |
| `neutral.600` | `#2E2E3F` | `--neutral-600` |
| `neutral.700` | `#1E1E2C` | `--neutral-700` |
| `neutral.800` | `#141420` | `--neutral-800` |
| `neutral.900` | `#0E0E1A` | `--neutral-900` |
| `neutral.950` | `#0A0A10` | `--neutral-950` (page bg) |

#### Surface Overlays (Dark)

| Token | Value | Usage |
|-------|-------|-------|
| `surface-elevated` | `#161625` | Cards above page bg |
| `surface-overlay` | `#1C1C2E` | Modals, dropdowns, popovers |
| `surface-glass` | `rgba(14,14,26,0.70)` | Glass-card with `backdrop-blur-md` |

### 3.3 Semantic Colors

| Token | Light Hex | Dark Hex | Usage |
|-------|-----------|----------|-------|
| `success` | `#16A34A` | `#22C55E` | Success states, confirmed |
| `warning` | `#D97706` | `#F59E0B` | Warnings, rate limits |
| `error` | `#DC2626` | `#EF4444` | Errors, failures, destructive |
| `info` | `#2563EB` | `#3B82F6` | Info banners, tooltips |

### 3.4 Data Visualization (Dark-first)

| Name | Hex | Usage |
|------|-----|-------|
| `chart-1` | `#7B61FF` | Primary brand data |
| `chart-2` | `#3B82F6` | Secondary metric |
| `chart-3` | `#22C55E` | Success/TPS |
| `chart-4` | `#F59E0B` | Latency |
| `chart-5` | `#EC4899` | Errors |
| `chart-6` | `#06B6D4` | Throughput |

---

## 4. Spacing

基于 **4px 网格系统**，所有间距为 4 的整数倍。

| Token | Value | rem | Usage |
|-------|-------|-----|-------|
| `space-1` | 4px | 0.25rem | Inline micro-gap, icon-text |
| `space-2` | 8px | 0.5rem | Tight element gap |
| `space-3` | 12px | 0.75rem | Component internal |
| `space-4` | 16px | 1rem | Standard gap (default) |
| `space-6` | 24px | 1.5rem | Section padding |
| `space-8` | 32px | 2rem | Block separation |
| `space-12` | 48px | 3rem | Major section gap |
| `space-16` | 64px | 4rem | Page section vertical |
| `space-24` | 96px | 6rem | Hero/landing blocks |

### Layout Constraints

| Breakpoint | Max-Width | Padding |
|-----------|-----------|---------|
| All | – | `16px` (inline `space-4`) |
| `md` (768+) | – | `24px` |
| `lg` (1024+) | `1024px` | `32px` |
| `xl` (1280+) | `1200px` | auto |
| `2xl` (1536+) | `1320px` | auto |

---

## 5. Components

### 5.1 Buttons

| Variant | Background | Text | Border | Hover |
|---------|-----------|------|--------|-------|
| `primary` | `brand.600` (#3B2FCE) | white | none | `brand.700` (#2D22A3) |
| `secondary` | `neutral.700` | `neutral.100` | none | `neutral.600` |
| `outline` | transparent | `neutral.100` | 1px `neutral.600` | bg `neutral.800` |
| `ghost` | transparent | `neutral.300` | none | bg `neutral.800`, text white |
| `destructive` | `error` | white | none | darker error |

| Size | Height | Padding-X | Font | Radius |
|------|--------|-----------|------|--------|
| `sm` | 32px | 12px | 14px | 6px |
| `md` (default) | 40px | 16px | 14px | 8px |
| `lg` | 48px | 24px | 16px | 10px |
| `icon-sm` | 32×32px | – | – | 6px |
| `icon-md` | 40×40px | – | – | 8px |

**Focus ring**: `2px solid brand.500`, offset 2px  
**Disabled**: `opacity: 0.4`, `pointer-events: none`  
**Loading**: spinner 16×16px, gap 8px before label

### 5.2 Cards

| Level | Background | Border | Shadow | Radius |
|-------|-----------|--------|--------|--------|
| `default` | `surface-elevated` | 1px `neutral.600` | none | 12px |
| `hover` | `surface-elevated` | 1px `neutral.500` | `0 4px 24px rgba(59,47,206,0.08)` | 12px |
| `glass` | `surface-glass` | 1px `rgba(255,255,255,0.06)` | `backdrop-blur-md` | 16px |

**Card padding**: `24px` (space-6)  
**Card gap (grid)**: `24px` (space-6)

### 5.3 Inputs

| State | Background | Border | Text |
|-------|-----------|--------|------|
| `default` | `neutral.800` | 1px `neutral.600` | `neutral.50` |
| `hover` | `neutral.800` | 1px `neutral.500` | `neutral.50` |
| `focus` | `neutral.800` | 2px `brand.500`, glow `rgba(123,97,255,0.15)` | white |
| `error` | `neutral.800` | 2px `error` | `neutral.50` |
| `disabled` | `neutral.700` | 1px `neutral.600` | `neutral.400` |

**Height**: 40px (md) / 32px (sm)  
**Padding X**: 12px  
**Radius**: 8px  
**Placeholder**: `neutral.400`

### 5.4 Select / Dropdown

- **Panel**: `surface-overlay`, border 1px `neutral.600`, radius 10px
- **Item height**: 36px, padding 8px 12px
- **Item hover**: bg `neutral.700`
- **Item selected**: bg `brand.600/15`, text `brand.300`, checkmark left

### 5.5 Badges / Tags

| Variant | Background | Text | Border |
|---------|-----------|------|--------|
| `neutral` | `neutral.700` | `neutral.200` | none |
| `brand` | `rgba(59,47,206,0.15)` | `brand.300` | 1px `rgba(123,97,255,0.25)` |
| `success` | `rgba(34,197,94,0.12)` | `#4ADE80` | 1px `rgba(34,197,94,0.20)` |
| `warning` | `rgba(245,158,11,0.12)` | `#FBBF24` | 1px `rgba(245,158,11,0.20)` |
| `error` | `rgba(239,68,68,0.12)` | `#F87171` | 1px `rgba(239,68,68,0.20)` |

**Height**: 24px / 28px  
**Padding**: 4px 10px  
**Radius**: 9999px (full pill)  
**Font**: 12px, weight 500

### 5.6 Tables

| Element | Style |
|---------|-------|
| Header bg | `neutral.700` |
| Header text | 12px, weight 500, `neutral.300`, uppercase tracking `+0.05em` |
| Row hover | bg `rgba(255,255,255,0.03)` |
| Cell padding | 12px 16px |
| Border | 1px `neutral.600`, horizontal only |
| Radius | 10px (wrapper) |

### 5.7 Tooltips

- **Background**: `neutral.900`, border 1px `neutral.700`
- **Text**: 12px, `neutral.100`
- **Padding**: 6px 10px, radius 6px
- **Arrow**: 4px

### 5.8 Code Blocks

- **Background**: `#0D0D1A` (deeper than page)
- **Border**: 1px `neutral.700`, radius 10px
- **Font**: `JetBrains Mono`, 13px, line-height 1.6
- **Padding**: 16px
- **Header bar**: 36px height, macOS-style dots (×/–/+), filename label 12px `neutral.400`

### 5.9 Dividers

| Variant | Style |
|---------|-------|
| `default` | 1px `neutral.600`, full width |
| `subtle` | 1px `rgba(255,255,255,0.04)` |
| `gradient` | 1px `linear-gradient(90deg, transparent, neutral.500, transparent)` |

---

## 6. Dark / Light Mode

### 6.1 Mode Strategy

- **Dark-first 设计**: 默认深色，Light 作为备选
- 所有颜色通过 CSS 自定义属性 (`--color-*`) 切换
- `prefers-color-scheme` 自动检测，手动 switcher 覆盖并 persist 到 `localStorage` key `AiFlowHub-theme`

### 6.2 Light Mode Palette（品牌浅紫）

| Element | Hex | CSS Variable |
|---------|-----|-------------|
| Page BG | #F5F3FF | var(--brand-50) |
| Surface | #EDE9FE | var(--brand-100) |
| Elevated / Cards | #FFFFFF | white |
| Overlay | #FFFFFF | white |
| Body text | #151822 | var(--neutral-900) |
| Muted text | #4B5060 | var(--neutral-600) |
| Border | #DDD6FE | var(--brand-200) |
| Hero BG | linear-gradient(135deg, #F5F3FF, #EDE9FE) | brand gradient |

### 6.3 Semantic Mode Map

| Color | Light Mode | Dark Mode |
|-------|-----------|-----------|
| Page BG | #F5F3FF (brand-50) | #0A0A10 |
| Surface | #EDE9FE (brand-100) | #141420 |
| Elevated | #FFFFFF | #161625 |
| Overlay | #FFFFFF | #1C1C2E |
| Body text | #151822 | #EEEEF2 |
| Muted text | #4B5060 | #707088 |
| Border | #DDD6FE (brand-200) | #2E2E3F |

### 6.4 Transition

- Mode switch: `background-color 300ms ease, color 300ms ease, border-color 300ms ease`
- 应用在 `html` / `body` 层级

---

## 7. Breakpoints

| Name | Min-Width | Layout |
|------|-----------|--------|
| `sm` | 640px | 单列全宽，hamburger nav |
| `md` | 768px | 双列卡片，侧栏展开 |
| `lg` | 1024px | 侧栏常驻，三列 dashboard |
| `xl` | 1280px | 宽屏布局，侧栏 + 主 + 辅助面板 |
| `2xl` | 1536px | 最大宽度容器，居中 |

### 7.1 Container

```css
.container {
  width: 100%;
  margin: 0 auto;
  padding: 0 16px;
}
@media (min-width: 768px)  { .container { padding: 0 24px; } }
@media (min-width: 1024px) { .container { max-width: 1024px; padding: 0 32px; } }
@media (min-width: 1280px) { .container { max-width: 1200px; } }
@media (min-width: 1536px) { .container { max-width: 1320px; } }
```

### 7.2 Sidebar

| Breakpoint | Width | State |
|-----------|-------|-------|
| `< md` (640–767px) | 100vw | Overlay, triggered by hamburger |
| `md` – `lg` (768–1023px) | 56px | Collapsed icons-only |
| `>= lg` (1024px+) | 240px | Expanded, fixed |

---

## 8. Motion

### 8.1 Duration Tokens

| Token | Value | Usage |
|-------|-------|-------|
| `duration-instant` | 100ms | Micro-interactions, checkbox, toggle |
| `duration-fast` | 150ms | Hover color change, focus ring |
| `duration-normal` | 200ms | Button press, modal backdrop, tab switch |
| `duration-slow` | 300ms | Page transitions, modal open/close, sidebar expand |
| `duration-slower` | 500ms | Hero animations, on-scroll reveals |

### 8.2 Easing Curves

| Token | Cubic-Bezier | Usage |
|-------|-------------|-------|
| `ease-default` | `cubic-bezier(0.4, 0, 0.2, 1)` | Standard Material-like |
| `ease-in` | `cubic-bezier(0.4, 0, 1, 1)` | Entering screen (modals) |
| `ease-out` | `cubic-bezier(0, 0, 0.2, 1)` | Exiting screen, fade-outs |
| `ease-emphasized` | `cubic-bezier(0.05, 0.7, 0.1, 1)` | Hero entrance, scale transitions |
| `ease-spring` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | Bouncy micro-interactions |

### 8.3 Animation Patterns

| Pattern | Description |
|---------|-------------|
| **Fade in** | `opacity 0→1`, 200ms `ease-out` |
| **Slide up** | `translateY(8px)→0` + fade, 300ms `ease-emphasized` |
| **Scale in** | `scale(0.95)→1` + fade, 200ms `ease-emphasized` |
| **Stagger list** | Children delay `index × 50ms`, 300ms `ease-out` each |
| **Page transition** | Cross-fade 300ms, layout shift `ease-default` |

### 8.4 Reduced Motion

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

### 8.5 Loading States

| Context | Style |
|---------|-------|
| **Spinner** | SVG circle, 2px stroke, `brand.500`, 600ms linear infinite |
| **Skeleton** | `neutral.700` pulse (dark) / `neutral.200` pulse (light), radius 6px |
| **Progress bar** | 4px height, `neutral.700` track, `brand.500` fill, `ease-default` |
| **Shimmer** | `linear-gradient(90deg, transparent, rgba(255,255,255,0.05), transparent)` sweep 1.5s |

---

## 9. Elevation / Shadows

| Level | Value | Usage |
|-------|-------|-------|
| `shadow-sm` | `0 1px 2px rgba(0,0,0,0.3)` | Input borders, subtle lift |
| `shadow-md` | `0 4px 12px rgba(0,0,0,0.4)` | Cards, dropdowns |
| `shadow-lg` | `0 8px 32px rgba(0,0,0,0.5)` | Modals, drawers |
| `shadow-glow` | `0 0 24px rgba(59,47,206,0.25)` | Brand emphasis, featured cards |

**Light mode equivalent**: same structure, opacity reduced 40%, no pure-black.

---

## 10. Iconography

- **Library**: Lucide Icons (primary), Phosphor Icons (supplementary)
- **Sizes**: 16px (inline), 20px (UI default), 24px (standalone), 32px (feature)
- **Stroke**: 1.5px (small), 2px (medium/large)
- **Color**: inherit from text or `neutral.400` for muted icons
- **Brand icons**: `brand.500` when interactive/primary

---

## 11. Grid & Layout

- **Base grid**: CSS Grid 12-column
- **Gutter**: 24px (space-6)
- **Sidebar + Content**: `240px 1fr`
- **Dashboard cards**: `repeat(auto-fill, minmax(280px, 1fr))`
- **Form layouts**: `repeat(2, 1fr)` for 2-column, stack to 1-col on `< md`

---

## Appendix: Tailwind Config (Reference)

```js
// tailwind.config.js — design tokens mapped
module.exports = {
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#F5F3FF', 100: '#EDE9FE', 200: '#DDD6FE',
          300: '#C4B5FD', 400: '#A78BFA', 500: '#7B61FF',
          600: '#3B2FCE', 700: '#2D22A3', 800: '#1E1670',
          900: '#120D4A', 950: '#0B0826',
        },
        neutral: {
          0: '#FFFFFF', 50: '#F8F8FC', 100: '#EEEEF2',
          200: '#D4D4DC', 300: '#A0A0B0', 400: '#707088',
          500: '#4A4A5E', 600: '#2E2E3F', 700: '#1E1E2C',
          800: '#141420', 900: '#0E0E1A', 950: '#0A0A10',
        },
      },
      fontFamily: {
        sans: ['Inter Variable', 'Inter', 'SF Pro Display', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Fira Code', 'ui-monospace', 'monospace'],
      },
      borderRadius: {
        sm: '6px', md: '8px', lg: '10px', xl: '12px', '2xl': '16px',
      },
      boxShadow: {
        glow: '0 0 24px rgba(59,47,206,0.25)',
      },
    },
  },
};
```

---

> **Next**: 此 DESIGN.md 驱动 `components.json` (shadcn/ui) 主题变量、
> Tailwind `theme.extend` 以及 Figma 设计 Token 同步。
> 所有新增组件必须先引用本文档定义的 token，不可 ad-hoc 硬编码色值。
