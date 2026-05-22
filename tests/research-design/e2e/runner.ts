import { test, expect, type Page, type ConsoleMessage } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

type Step =
  | { goto: string }
  | { click: string }
  | { setInputFiles: [string, string] }
  | { waitForSelector: string; timeout?: number }
  | { expect: { selector?: string; containsText?: string; url?: string } }
  | { fetch: string; expectStatus: number }
  | { expectNoConsoleError: boolean }
  | { expectNoNetworkFailure: string[] };

type Scenario = { name: string; steps: Step[] };
type ScenarioFile = { slug: string; baseUrl: { local: string; prod?: string }; scenarios: Scenario[] };

export function runScenarios(scenarioFilePath: string) {
  const file: ScenarioFile = JSON.parse(readFileSync(scenarioFilePath, 'utf8'));

  test.describe(`scenarios: ${file.slug}`, () => {
    for (const scenario of file.scenarios) {
      test(scenario.name, async ({ page, request, baseURL }) => {
        const consoleErrors: string[] = [];
        const networkFailures: string[] = [];

        page.on('console', (msg: ConsoleMessage) => {
          if (msg.type() === 'error') consoleErrors.push(msg.text());
        });
        page.on('response', (resp) => {
          if (resp.status() >= 400) networkFailures.push(`${resp.status()} ${resp.url()}`);
        });

        for (const step of scenario.steps) {
          await runStep(page, request, baseURL!, step, consoleErrors, networkFailures);
        }
      });
    }
  });
}

async function runStep(
  page: Page,
  request: import('@playwright/test').APIRequestContext,
  baseURL: string,
  step: Step,
  consoleErrors: string[],
  networkFailures: string[]
): Promise<void> {
  if ('goto' in step) {
    await page.goto(step.goto);
  } else if ('click' in step) {
    await page.locator(step.click).first().click();
  } else if ('setInputFiles' in step) {
    const [selector, path] = step.setInputFiles;
    await page.setInputFiles(selector, resolve(path));
  } else if ('waitForSelector' in step) {
    await page.waitForSelector(step.waitForSelector, { timeout: step.timeout ?? 5000 });
  } else if ('expect' in step) {
    const e = step.expect;
    if (e.selector && e.containsText) {
      await expect(page.locator(e.selector)).toContainText(e.containsText, { ignoreCase: true });
    }
    if (e.url) {
      await expect(page).toHaveURL(new RegExp(e.url.replace(/\//g, '\\/')));
    }
  } else if ('fetch' in step) {
    const resp = await request.get(new URL(step.fetch, baseURL).toString());
    expect(resp.status()).toBe(step.expectStatus);
  } else if ('expectNoConsoleError' in step) {
    expect(consoleErrors, `console errors: ${consoleErrors.join('\n')}`).toEqual([]);
  } else if ('expectNoNetworkFailure' in step) {
    const matched = networkFailures.filter((f) => step.expectNoNetworkFailure.some((p) => f.includes(p)));
    expect(matched, `network failures: ${matched.join('\n')}`).toEqual([]);
  }
}
