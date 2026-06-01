import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

// Supported locales
const LOCALES = ["en", "ru", "tr"];
const DEFAULT_LOCALE = "en";

// Paths that require authentication
const PROTECTED_PREFIXES = [
  "/dashboard",
  "/api-keys",
  "/usage",
  "/recharge",
  "/profile",
];

const AUTH_PAGES = ["/login", "/register", "/forgot-password", "/reset-password"];

export default function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const token = req.cookies.get("ai_api_agg_token")?.value;

  // Detect locale from cookie or accept-language header
  const cookieLocale = req.cookies.get("NEXT_LOCALE")?.value;
  const acceptLang = req.headers.get("accept-language") || "";
  let locale = DEFAULT_LOCALE;

  if (cookieLocale && LOCALES.includes(cookieLocale)) {
    locale = cookieLocale;
  } else {
    // Parse accept-language (e.g., "ru-RU,ru;q=0.9,en;q=0.8")
    for (const lang of acceptLang.split(",")) {
      const code = lang.trim().split(";")[0].split("-")[0];
      if (LOCALES.includes(code)) {
        locale = code;
        break;
      }
    }
  }

  // Auth redirects
  const isProtected = PROTECTED_PREFIXES.some(
    (p) => pathname === p || pathname.startsWith(p + "/"),
  );

  const isAuthPage = AUTH_PAGES.some(
    (p) => pathname === p || pathname.startsWith(p + "/"),
  );

  if (isProtected && !token) {
    const loginUrl = new URL("/login", req.url);
    loginUrl.searchParams.set("redirect", pathname);
    return NextResponse.redirect(loginUrl);
  }

  if (isAuthPage && token) {
    return NextResponse.redirect(new URL("/dashboard", req.url));
  }

  if (pathname === "/" && token) {
    return NextResponse.redirect(new URL("/dashboard", req.url));
  }

  // Pass locale to i18n via request header
  const requestHeaders = new Headers(req.headers);
  requestHeaders.set("x-next-intl-locale", locale);

  return NextResponse.next({
    request: { headers: requestHeaders },
  });
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon\\.svg|flags/|api/).*)",
  ],
};
