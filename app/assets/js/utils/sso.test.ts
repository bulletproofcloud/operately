import { isSsoOnly, oidcAuthUrl, shouldAutoStartSso, ssoErrorMessage, startSsoLogin } from "./sso";

function stubWindow(appConfig: Partial<AppConfig>, search = "", pathname = "/") {
  Object.defineProperty(global, "window", {
    configurable: true,
    value: {
      appConfig: { allowLoginWithEmail: false, allowLoginWithGoogle: false, configured: true, ...appConfig },
      location: { search, pathname, assign: jest.fn() },
    },
  });
}

describe("isSsoOnly", () => {
  it("is true when the server says so and the instance is configured", () => {
    stubWindow({ ssoOnly: true });
    expect(isSsoOnly()).toBe(true);
  });

  it("is false before setup", () => {
    stubWindow({ ssoOnly: true, configured: false });
    expect(isSsoOnly()).toBe(false);
  });

  it("is false otherwise", () => {
    stubWindow({ ssoOnly: false });
    expect(isSsoOnly()).toBe(false);
  });
});

describe("oidcAuthUrl", () => {
  beforeEach(() => stubWindow({}));

  it("is the bare route without params", () => {
    expect(oidcAuthUrl({})).toBe("/accounts/auth/oidc");
  });

  it("carries redirect_to and invite_token", () => {
    expect(oidcAuthUrl({ redirectTo: "/c/goals", inviteToken: "tok" })).toBe(
      "/accounts/auth/oidc?redirect_to=%2Fc%2Fgoals&invite_token=tok",
    );
  });

  it("drops redirect_to values that are not same-site paths", () => {
    expect(oidcAuthUrl({ redirectTo: "//evil.example" })).toBe("/accounts/auth/oidc");
    expect(oidcAuthUrl({ redirectTo: "https://evil.example" })).toBe("/accounts/auth/oidc");
    expect(oidcAuthUrl({ redirectTo: "/\t/evil.example" })).toBe("/accounts/auth/oidc");
    expect(oidcAuthUrl({ redirectTo: "/\n/evil.example" })).toBe("/accounts/auth/oidc");
    expect(oidcAuthUrl({ redirectTo: "/\\evil.example" })).toBe("/accounts/auth/oidc");
  });
});

describe("ssoErrorMessage", () => {
  it("maps known codes", () => {
    stubWindow({ oidcProviderName: "Authentik" });
    expect(ssoErrorMessage("no_account")).toBe("No Operately account for this email. Ask an admin for an invite.");
    expect(ssoErrorMessage("email_not_verified")).toBe("Authentik did not confirm your email address.");
  });

  it("is null without a code and generic for unknown codes", () => {
    stubWindow({});
    expect(ssoErrorMessage(null)).toBeNull();
    expect(ssoErrorMessage("weird")).toBe("Sign-in failed. Please try again.");
  });

  it.each(["__proto__", "constructor", "toString", "hasOwnProperty"])(
    "falls back to the generic message for inherited property %s",
    (code) => {
      stubWindow({});
      expect(ssoErrorMessage(code)).toBe("Sign-in failed. Please try again.");
    },
  );
});

describe("startSsoLogin", () => {
  it("navigates the whole page to the provider", () => {
    stubWindow({ ssoOnly: true }, "?invite_token=tok");
    startSsoLogin("/c/goals");
    expect(window.location.assign).toHaveBeenCalledWith(
      "/accounts/auth/oidc?redirect_to=%2Fc%2Fgoals&invite_token=tok",
    );
  });
});

describe("shouldAutoStartSso", () => {
  it("is true for anonymous visitors in SSO-only mode without an error", () => {
    stubWindow({ ssoOnly: true });
    expect(shouldAutoStartSso(null)).toBe(true);
  });

  it("is false when there is an SSO error", () => {
    stubWindow({ ssoOnly: true });
    expect(shouldAutoStartSso("failed")).toBe(false);
  });

  it("is false for a logged-in account", () => {
    stubWindow({ ssoOnly: true, account: { id: "acc" } } as any);
    expect(shouldAutoStartSso(null)).toBe(false);
  });

  it("is false when not SSO-only", () => {
    stubWindow({ ssoOnly: false });
    expect(shouldAutoStartSso(null)).toBe(false);
  });
});
