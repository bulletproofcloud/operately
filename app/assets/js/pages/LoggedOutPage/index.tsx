import * as Pages from "@/components/Pages";
import * as Paper from "@/components/PaperContainer";
import * as React from "react";

import { OperatelyLogo } from "@/components/OperatelyLogo";
import { PageModule } from "@/routes/types";
import { PrimaryButton } from "turboui";

export default { name: "LoggedOutPage", loader: Pages.emptyLoader, Page } as PageModule;

function Page() {
  return (
    <Pages.Page title={["Signed out"]} testId="logged-out-page">
      <Paper.Root size="tiny">
        <Paper.Body>
          <div className="py-8 sm:px-4 sm:py-4">
            <OperatelyLogo width="40px" height="40px" />
            <h1 className="text-2xl font-bold mt-4">You've signed out</h1>
            <p className="text-content-dimmed mb-8">You can close this tab, or sign in again.</p>
            <PrimaryButton linkTo="/log_in" testId="sign-in-again">
              Sign in again
            </PrimaryButton>
          </div>
        </Paper.Body>
      </Paper.Root>
    </Pages.Page>
  );
}
