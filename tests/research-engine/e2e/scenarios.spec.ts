import { runScenarios } from '../../research-design/e2e/runner';

const path = process.env.E2E_SCENARIOS_PATH;
if (!path) {
  throw new Error('E2E_SCENARIOS_PATH env var required');
}
runScenarios(path);
