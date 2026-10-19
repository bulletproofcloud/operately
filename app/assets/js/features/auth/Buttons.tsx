import * as React from "react";
import { oidcAuthUrl } from "@/utils/sso";
import { AuthProviderButton, GoogleLogo, IconMail, IconShieldLock } from "turboui";

export function SignUpWithEmail({
  inviteToken,
  redirectTo,
}: {
  inviteToken?: string | null;
  redirectTo?: string | null;
}) {
  return (
    <AuthProviderButton
      title="Sign up with email"
      link={signupEmailPath(inviteToken, redirectTo)}
      icon={<IconMail size={24} className="text-content-dimmed" />}
      testId="sign-up-with-email"
    />
  );
}

export function SignInWithGoogleButton() {
  return (
    <AuthProviderButton
      title="Sign in with Google"
      link={getGoogleAuthUrl()}
      icon={<GoogleLogo />}
      external
      testId="sign-in-with-google"
    />
  );
}

export function SignUpWithGoogleButton() {
  return (
    <AuthProviderButton
      title="Sign up with Google"
      link={getGoogleAuthUrl()}
      icon={<GoogleLogo />}
      external
      testId="sign-up-with-google"
    />
  );
}

export function SignInWithOidcButton() {
  return (
    <AuthProviderButton
      title={`Sign in with ${window.appConfig.oidcProviderName || "SSO"}`}
      link={oidcLinkFromLocation()}
      icon={<IconShieldLock size={24} className="text-content-dimmed" />}
      external
      testId="sign-in-with-oidc"
    />
  );
}

export function SignUpWithOidcButton() {
  return (
    <AuthProviderButton
      title={`Sign up with ${window.appConfig.oidcProviderName || "SSO"}`}
      link={oidcLinkFromLocation()}
      icon={<IconShieldLock size={24} className="text-content-dimmed" />}
      external
      testId="sign-up-with-oidc"
    />
  );
}

function oidcLinkFromLocation(): string {
  const params = new URLSearchParams(window.location.search);
  return oidcAuthUrl({ redirectTo: params.get("redirect_to"), inviteToken: params.get("invite_token") });
}

function signupEmailPath(inviteToken?: string | null, redirectTo?: string | null): string {
  const params = new URLSearchParams();

  if (inviteToken) {
    params.set("invite_token", inviteToken);
  }

  if (redirectTo) {
    params.set("redirect_to", redirectTo);
  }

  const query = params.toString();

  if (query) {
    return `/sign_up/email?${query}`;
  } else {
    return "/sign_up/email";
  }
}

function getGoogleAuthUrl(): string {
  const params = new URLSearchParams(window.location.search);
  const redirectTo = params.get("redirect_to");
  const inviteToken = params.get("invite_token");

  const search = new URLSearchParams();

  if (redirectTo) {
    search.set("redirect_to", redirectTo);
  }

  if (inviteToken) {
    search.set("invite_token", inviteToken);
  }

  const query = search.toString();

  if (query) {
    return `/accounts/auth/google?${query}`;
  }

  return "/accounts/auth/google";
}
