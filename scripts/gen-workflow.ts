// Test only: write .github/workflows/dynenv.yml with the generator of a monk-agent checkout (cluster
// mode, this repo's settings), and point build-images and deploy at the copies in .github/actions
// (see sync-actions.sh).
//
// Usage: deno run -A --config ../monk-agent/deno.json scripts/gen-workflow.ts [mode] [monk-agent dir]
//   mode: cluster (default) or cloud
import { generateDynEnvWorkflow } from "../../monk-agent/src/services/capsule/workflow.ts";

const mode = Deno.args[0] === "cloud" ? "cloud" : "cluster";
let yml = generateDynEnvWorkflow({
  entrypoint: "capsule-sample/stack",
  capsuleMode: mode,
  peerPoolTag: "capsule-pool",
  secretContext: "monk-capsules",
  clusterNamePrefix: "monk-capsule-sample",
  excludeBranches: ["main", "master"],
  cloudProviderSecretKeys: mode === "cloud" ? ["DO_API_TOKEN"] : [],
  workloadSecretKeys: ["greeting"],
  defaultBaseBranch: "main",
});
for (const action of ["build-images", "deploy"]) {
  yml = yml.replaceAll(
    `uses: monk-io/monk-actions/${action}@v1`,
    `uses: ./.github/actions/${action}`,
  );
}
await Deno.writeTextFile(".github/workflows/dynenv.yml", yml);
console.log(`wrote dynenv.yml (${mode} mode)`);
