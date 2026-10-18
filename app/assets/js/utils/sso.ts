const ERROR_MESSAGES: Record<string, (provider: string) => string> = {
  no_account: () => "No Operately account for this email. Ask an admin for an invite.",
  email_not_verified: (provider) => `${provider} did not confirm your email address.`,
  not_configured: () => "Single sign-on is not configured.",
  failed: () => "Sign-in failed. Please try again.",
};

export function isSsoOnly(): boolean {
  return Boolean(window.appConfig.ssoOnly) && window.appConfig.configured !== false;
}

// On /log_in, auto-start SSO only for anonymous visitors with no pending SSO error
// (mirrors the Elixir plug, which skips logged-in accounts).
export function shouldAutoStartSso(ssoError: string | null): boolean {
  return isSsoOnly() && !ssoError && !window.appConfig.account?.id;
}

export function oidcAuthUrl({
  redirectTo,
  inviteToken,
}: {
  redirectTo?: string | null;
  inviteToken?: string | null;
}): string {
  const search = new URLSearchParams();
  const safe = safeRedirectTo(redirectTo);

  if (safe) search.set("redirect_to", safe);
  if (inviteToken) search.set("invite_token", inviteToken);

  const query = search.toString();
  return query ? `/accounts/auth/oidc?${query}` : "/accounts/auth/oidc";
}

export function ssoErrorMessage(code: string | null): string | null {
  if (!code) return null;

  const provider = window.appConfig.oidcProviderName || "SSO";
  return (ERROR_MESSAGES[code] ?? ERROR_MESSAGES.failed!)(provider);
}

export function startSsoLogin(redirectTo: string | null): void {
  const inviteToken = new URLSearchParams(window.location.search).get("invite_token");
  window.location.assign(oidcAuthUrl({ redirectTo, inviteToken }));
}

// Same rule as OperatelyWeb.Plugs.SsoOnlyLoginRedirect.safe_redirect_to/1:
// a same-site path, not protocol-relative, with no control characters or backslashes.
function safeRedirectTo(value?: string | null): string | null {
  if (!value || !value.startsWith("/")) return null;
  if (value.startsWith("//")) return null;
  if (/[\x00-\x1f\x7f\\]/.test(value)) return null;
  return value;
}
