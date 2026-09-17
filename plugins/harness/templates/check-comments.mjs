#!/usr/bin/env node
// Comment linter: hard-fails on issue numbers, dates and ruling or attribution citations
// in comments (comments say why, never history), and reports comment density and
// past-tense changelog verbs per file so density regressions stay visible.
//
// Installed into a project's scripts/ by /harness:harness-init, which fills the CONFIG
// block. Modes:
//   --diff [--base <branch>]  fail only on ADDED comment lines vs the base branch: the
//                             ratchet, safe to wire into lint on a tree with a backlog
//   --report                  density table over the whole tree, never fails
//   --file <path>             one file, violations and changelog hits
//   (none)                    whole-tree hard-fail plus density warnings
//
// A comment can be load-bearing for a test that scans the file as text: a comment-only
// edit still runs the tests before it is committed.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { execFileSync } from 'node:child_process';

// ---- CONFIG: filled by harness-init for this project's stack ---------------------
const CONFIG = {
  srcRoot: '{{SRC_ROOT}}',                       // e.g. 'src'
  extensions: ['{{EXT_LIST}}'],                  // e.g. '.ts', '.tsx'
  lineComment: '{{LINE_COMMENT}}',               // e.g. '//' or '#'
  blockOpen: '{{BLOCK_OPEN}}',                   // e.g. '/*'; '' if the language has none
  blockClose: '{{BLOCK_CLOSE}}',                 // e.g. '*/'
  blockContinuation: '{{BLOCK_CONTINUATION}}',   // e.g. '*'; the prefix of a block body line
  escapePrefix: '{{ESCAPE_PREFIX}}',             // a comment starting with this is skipped, e.g. '// TUNABLE'
  ruleCitation: '{{RULE_CITATION}}',             // named in the failure message, e.g. '.claude/rules/style.md'
  defaultBranch: '{{DEFAULT_BRANCH}}',
  densityWarnThreshold: 0.25,
  skipDirs: ['node_modules', 'dist', 'build', 'target', '.git'],
};
// ----------------------------------------------------------------------------------

const ISSUE_REF = /#\d+\b/;
const ISO_DATE = /\b20\d{2}-\d{2}-\d{2}\b/;
const MONTH_YEAR = /\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?\s+\d{1,2},?\s+20\d{2}\b/i;
const RULING_OR_ATTRIBUTION = /\b(owner ruling|ruled|per owner|owner:)\b/i;
const CHANGELOG_VERB = /\b(added|removed|changed|renamed|replaced|refactored|deleted|used to|previously|now uses|was)\b/i;

const HARD_FAIL_PATTERNS = [
  { name: 'issue reference', re: ISSUE_REF },
  { name: 'ISO date', re: ISO_DATE },
  { name: 'month/year date', re: MONTH_YEAR },
  { name: 'ruling/attribution citation', re: RULING_OR_ATTRIBUTION },
];

const hasBlock = CONFIG.blockOpen.length > 0;
const isSource = (name) => CONFIG.extensions.some((e) => name.endsWith(e));
const isEscaped = (trimmed) => CONFIG.escapePrefix.length > 0 && trimmed.startsWith(CONFIG.escapePrefix);

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (CONFIG.skipDirs.includes(entry)) continue;
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) walk(full, out);
    else if (isSource(entry)) out.push(full);
  }
  return out;
}

// Tracks block-comment state across lines; a line with code and a trailing line comment
// counts as a comment line, and only the comment portion is scanned for banned patterns.
function scanFile(path) {
  const lines = readFileSync(path, 'utf8').split('\n');
  let inBlock = false;
  let commentLines = 0;
  const violations = [];
  const changelogHits = [];

  lines.forEach((line, i) => {
    const lineNo = i + 1;
    const trimmed = line.trim();
    let commentText = '';

    if (inBlock) {
      commentText = line;
      if (trimmed.includes(CONFIG.blockClose)) inBlock = false;
    } else {
      const blockStart = hasBlock ? line.indexOf(CONFIG.blockOpen) : -1;
      const lineStart = line.indexOf(CONFIG.lineComment);
      if (blockStart !== -1 && (lineStart === -1 || blockStart < lineStart)) {
        commentText = line.slice(blockStart);
        if (!line.slice(blockStart).includes(CONFIG.blockClose)) inBlock = true;
      } else if (lineStart !== -1) {
        commentText = line.slice(lineStart);
      }
    }

    if (!commentText) return;
    commentLines++;
    if (isEscaped(trimmed)) return;

    for (const { name, re } of HARD_FAIL_PATTERNS) {
      if (re.test(commentText)) violations.push({ line: lineNo, name, text: trimmed });
    }
    if (CHANGELOG_VERB.test(commentText)) changelogHits.push({ line: lineNo, text: trimmed });
  });

  return { totalLines: lines.length, commentLines, violations, changelogHits };
}

// Diff mode sees added lines in isolation, with no block state across hunks: a line is a
// comment if it holds the line marker, opens a block, or starts with the continuation
// prefix. The banned patterns are self-contained on one line, so this is enough.
function commentPortionOfLine(line) {
  const trimmed = line.trim();
  const lineStart = line.indexOf(CONFIG.lineComment);
  if (lineStart !== -1) return line.slice(lineStart);
  if (hasBlock && (trimmed.startsWith(CONFIG.blockOpen) || trimmed.startsWith(CONFIG.blockContinuation))) return line;
  return null;
}

function runDiffMode(baseArg) {
  const defaultBranch = baseArg || CONFIG.defaultBranch || 'main';
  let base;
  try {
    base = execFileSync('git', ['merge-base', defaultBranch, 'HEAD'], { encoding: 'utf8' }).trim();
  } catch {
    base = defaultBranch;
  }

  let diffOutput;
  try {
    diffOutput = execFileSync('git', ['diff', '-U0', base, '--', CONFIG.srcRoot], {
      encoding: 'utf8',
      maxBuffer: 1024 * 1024 * 64,
    });
  } catch (err) {
    console.error(`check-comments: git diff against ${base} failed: ${err.message}`);
    process.exit(2);
  }

  const violations = [];
  let currentFile = null;
  let newLineNo = null;

  for (const line of diffOutput.split('\n')) {
    if (line.startsWith('+++ ')) {
      const path = line.slice(4).replace(/^b\//, '');
      currentFile = isSource(path) ? path : null;
      continue;
    }
    if (line.startsWith('@@')) {
      const m = line.match(/\+(\d+)/);
      newLineNo = m ? parseInt(m[1], 10) : null;
      continue;
    }
    if (!currentFile || newLineNo === null) continue;
    if (line.startsWith('+') && !line.startsWith('+++')) {
      const added = line.slice(1);
      const commentText = commentPortionOfLine(added);
      if (commentText && !isEscaped(added.trim())) {
        for (const { name, re } of HARD_FAIL_PATTERNS) {
          if (re.test(commentText)) {
            violations.push({ file: currentFile, line: newLineNo, name, text: added.trim() });
          }
        }
      }
      newLineNo++;
    } else if (!line.startsWith('-')) {
      newLineNo++;
    }
  }

  if (violations.length === 0) {
    console.log(`OK: no new comment-rule violations vs ${base}.`);
    process.exit(0);
  }
  console.error(`New comment-rule violations vs ${base} (${CONFIG.ruleCitation}: no issue numbers, dates or ruling citations in comments):\n`);
  for (const v of violations) console.error(`  ${v.file}:${v.line} [${v.name}] ${v.text}`);
  process.exit(1);
}

function main() {
  const argv = process.argv;
  if (argv.includes('--diff')) {
    const baseIdx = argv.indexOf('--base');
    runDiffMode(baseIdx !== -1 ? argv[baseIdx + 1] : undefined);
    return;
  }

  const fileIdx = argv.indexOf('--file');
  if (fileIdx !== -1) {
    const target = argv[fileIdx + 1];
    const { violations, changelogHits, totalLines, commentLines } = scanFile(target);
    console.log(`${target}: ${commentLines}/${totalLines} comment lines (${(100 * commentLines / totalLines).toFixed(1)}%)\n`);
    console.log('Hard violations (issue ref / date / ruling citation; must fix):');
    for (const v of violations) console.log(`  ${v.line}: [${v.name}] ${v.text}`);
    console.log('\nChangelog-verb hits (review; likely narrates history, not why):');
    for (const c of changelogHits) console.log(`  ${c.line}: ${c.text}`);
    process.exit(0);
  }

  const rows = walk(CONFIG.srcRoot).sort().map((f) => ({ file: relative('.', f), ...scanFile(f) }));
  const allViolations = rows.flatMap((r) => r.violations.map((v) => ({ file: r.file, ...v })));

  if (argv.includes('--report')) {
    const ranked = rows.filter((r) => r.totalLines > 0).sort((a, b) => b.commentLines / b.totalLines - a.commentLines / a.totalLines);
    console.log('file\tlines\tcomment_lines\tdensity\tchangelog_verbs\thard_violations');
    for (const r of ranked) {
      console.log(`${r.file}\t${r.totalLines}\t${r.commentLines}\t${(r.commentLines / r.totalLines).toFixed(3)}\t${r.changelogHits.length}\t${r.violations.length}`);
    }
    const totalLines = rows.reduce((s, r) => s + r.totalLines, 0);
    const totalComments = rows.reduce((s, r) => s + r.commentLines, 0);
    console.log(`\nTOTAL\t${totalLines}\t${totalComments}\t${(totalComments / totalLines).toFixed(3)}`);
    process.exit(0);
  }

  let failed = false;
  if (allViolations.length > 0) {
    failed = true;
    console.error(`Comment-rule violations (${CONFIG.ruleCitation}: no issue numbers, dates or ruling citations in comments):\n`);
    for (const v of allViolations) console.error(`  ${v.file}:${v.line} [${v.name}] ${v.text}`);
    console.error('');
  }
  const dense = rows.filter((r) => r.totalLines > 0 && r.commentLines / r.totalLines > CONFIG.densityWarnThreshold);
  if (dense.length > 0) {
    console.warn(`Comment density above ${CONFIG.densityWarnThreshold * 100}% (warning, not blocking):\n`);
    for (const r of dense.sort((a, b) => b.commentLines / b.totalLines - a.commentLines / a.totalLines)) {
      console.warn(`  ${r.file}: ${(100 * r.commentLines / r.totalLines).toFixed(1)}% (${r.commentLines}/${r.totalLines})`);
    }
    console.warn('');
  }
  if (failed) {
    console.error(`${allViolations.length} violation(s) across ${new Set(allViolations.map((v) => v.file)).size} file(s).`);
    process.exit(1);
  }
}

main();
