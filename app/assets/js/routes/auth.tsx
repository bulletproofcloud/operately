type LogOutResult = { result: "success" | "failure"; redirectUrl: string | null };
type LogInResult = "success" | "failure";

export async function logOut(): Promise<LogOutResult> {
  const res = await fetch("/accounts/log_out", { method: "DELETE", headers: autheaders() });

  if (res.status !== 200) return { result: "failure", redirectUrl: null };

  const body = await res.json().catch(() => ({}));
  return { result: "success", redirectUrl: typeof body.redirect_url === "string" ? body.redirect_url : null };
}

interface LogInOptions {
  redirectTo?: string | null;
  skipRedirect?: boolean;
  onSuccess?: () => void | Promise<void>;
}

export async function logIn(email: string, password: string, options: LogInOptions = {}): Promise<LogInResult> {
  const { redirectTo = null, skipRedirect = false, onSuccess } = options;
  const data = { email, password };

  const res = await fetch("/accounts/log_in", { method: "POST", headers: autheaders(), body: JSON.stringify(data) });

  if (res.status === 200) {
    if (onSuccess) {
      await onSuccess();
    }

    if (!skipRedirect) {
      if (redirectTo) {
        window.location.href = redirectTo;
      } else if (res.redirected) {
        window.location.href = res.url;
      } else {
        window.location.href = "/";
      }
    }

    return "success";
  } else {
    return "failure";
  }
}

function autheaders(): HeadersInit {
  const csrfToken = document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")?.content;

  return {
    "x-csrf-token": csrfToken,
    "Content-Type": "application/json",
  } as HeadersInit;
}
