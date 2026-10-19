import React from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";

import { GoogleLogo } from "../BrandIcons";
import { IconMail, IconShieldLock } from "../icons";
import { AuthProviderButton } from "./index";

/**
 * A full-width button for signing in or signing up through an identity provider.
 * The caller supplies the title, the link and the icon.
 */
const meta = {
  title: "Components/AuthProviderButton",
  component: AuthProviderButton,
  parameters: {
    layout: "centered",
  },
  decorators: [
    (Story) => (
      <div className="w-96">
        <Story />
      </div>
    ),
  ],
  tags: ["autodocs"],
} satisfies Meta<typeof AuthProviderButton>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Google: Story = {
  args: {
    title: "Sign in with Google",
    link: "#",
    icon: <GoogleLogo />,
    external: true,
    testId: "sign-in-with-google",
  },
};

export const Email: Story = {
  args: {
    title: "Sign up with email",
    link: "#",
    icon: <IconMail size={24} className="text-content-dimmed" />,
    external: true,
    testId: "sign-up-with-email",
  },
};

/**
 * Single sign-on through an OIDC provider; the app passes the configured provider name in the title.
 */
export const Oidc: Story = {
  args: {
    title: "Sign in with Authentik",
    link: "#",
    icon: <IconShieldLock size={24} className="text-content-dimmed" />,
    external: true,
    testId: "sign-in-with-oidc",
  },
};
