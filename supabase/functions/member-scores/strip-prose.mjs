// Drops the UI-only fields of the two data catalogs from the esbuild bundle.
// The engine reads HEALTH_DETAILS.*.{accentColor,scoreFromValue,getCurrentValue}
// and NUTRIENTS[].{key,rdaMale,rdaFemale,consumed} only; the copy, food sources,
// week trends and symptoms are for the Expo screens. Object literals tolerate a
// trailing comma, so the last kept field never breaks the syntax.
import { readFileSync, writeFileSync } from "node:fs";
const path = process.argv[2];
const lines = readFileSync(path, "utf8").split("\n");
const singleLine = /^\s+(subtitle|accentBg|chartColor|chartType|deltaSuffix|insightTitle|explanation|emoji|tagline|description|weekTrend|deficiencySymptoms|aiSuggestion): .*,?$/;
const blockStart = /^\s+(focusAreas|todayInContext|foodSources): \[$/;
const comment = /^\s+\/\/ /;
const out = [];
let depth = 0;
for (const line of lines) {
  if (depth > 0) {
    if (/^\s+\],?$/.test(line)) depth--;
    continue;
  }
  if (blockStart.test(line)) { depth = 1; continue; }
  if (singleLine.test(line) || comment.test(line)) continue;
  out.push(line);
}
writeFileSync(path, out.join("\n"));
