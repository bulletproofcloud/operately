import React from "react";
import classNames from "classnames";

import { DivLink } from "../Link";

export interface AuthProviderButtonProps {
  title: string;
  link: string;
  icon: React.ReactNode;
  external?: boolean;
  testId?: string;
}

export function AuthProviderButton({ title, link, icon, external, testId }: AuthProviderButtonProps) {
  const className = classNames(
    "w-full inline-flex gap-3 py-2.5 px-4",
    "bg-surface-base rounded-md shadow font-semibold",
    "hover:bg-surface-dimmed border border-surface-outline",
  );

  return (
    <DivLink to={link} className={className} data-test-id={testId} external={external}>
      {icon}
      <div className="text-center w-10/12">{title}</div>
    </DivLink>
  );
}
