// Type-checks the TypeScript and JavaScript snippets in the skills against the
// real @crowdstrike/foundry-js types. Snippets are fragments (undefined app
// types, missing imports, JSX without React), so only errors that involve a
// symbol declared in foundry-js are reported: a method that doesn't exist, a
// wrong argument shape, a missing argument.
//
// Usage: node tests/snippets/check.mjs [repo-root]
// Skip a block on purpose with `<!-- snippet-check: skip -->` on the line before it.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(process.argv[2] ?? path.join(here, '..', '..'));
const workDir = path.join(here, '.work');
// foundry-js, plus emittery, which types falcon.events
const SDK_DIRS = [`${path.sep}@crowdstrike${path.sep}foundry-js${path.sep}`, `${path.sep}emittery${path.sep}`];
const inSdk = (fileName) => SDK_DIRS.some((dir) => fileName.includes(dir));
const LANGS = { typescript: 'ts', ts: 'ts', tsx: 'tsx', javascript: 'js', js: 'js', jsx: 'jsx' };
const FENCE = /^(\s*)```(\w+)\s*$/;
const SKIP = '<!-- snippet-check: skip -->';

function markdownFiles() {
  const out = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.md')) out.push(full);
    }
  };
  walk(path.join(root, 'skills'));
  const agents = path.join(root, 'AGENTS.md');
  if (fs.existsSync(agents)) out.push(agents);
  return out;
}

function extractSnippets(file) {
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const snippets = [];
  for (let i = 0; i < lines.length; i++) {
    const open = lines[i].match(FENCE);
    if (!open || !(open[2] in LANGS)) continue;
    const prev = lines.slice(0, i).reverse().find((l) => l.trim() !== '');
    let end = i + 1;
    while (end < lines.length && !/^\s*```\s*$/.test(lines[end])) end++;
    if (prev?.trim() !== SKIP) {
      snippets.push({ file, ext: LANGS[open[2]], startLine: i + 2, body: lines.slice(i + 1, end) });
    }
    i = end;
  }
  return snippets;
}

// Wrap a snippet so top-level await, `this`-free statements, and a `falcon`
// variable all type-check. Imports move to the top; `export` is dropped, since
// declarations can't be exported from inside a function.
function wrap(snippet) {
  const imports = [];
  const importLines = []; // snippet line index of each hoisted import
  const body = [];
  for (const [index, line] of snippet.body.entries()) {
    if (/^\s*import\s.*\sfrom\s|^\s*import\s+['"]/.test(line)) {
      imports.push(line);
      importLines.push(index);
      body.push('');
    } else if (/^\s*export\s+(\{|\*)/.test(line)) {
      body.push('');
    } else {
      body.push(line.replace(/^(\s*)export\s+(default\s+)?/, '$1'));
    }
  }
  const isJs = snippet.ext === 'js' || snippet.ext === 'jsx';
  // Snippets often use the FalconApi type that an earlier block imported; without
  // the import it resolves to any and nothing on it gets checked.
  if (!isJs && /\bFalconApi\b/.test(body.join('\n')) && !imports.some((l) => /\bFalconApi\b/.test(l))) {
    imports.push("import FalconApi from '@crowdstrike/foundry-js';");
  }
  const param = isJs
    ? "/** @param {import('@crowdstrike/foundry-js').default} falcon */\nasync function __snippet(falcon) {\n{"
    : "async function __snippet(falcon: import('@crowdstrike/foundry-js').default) {\n{";
  const header = [...imports, 'export {};', param];
  return { text: [...header, ...body, '}', '}', ''].join('\n'), offset: header.join('\n').split('\n').length, importLines };
}

function involvesSdk(checker, node) {
  const declaredInSdk = (symbol) =>
    symbol?.declarations?.some((d) => inSdk(d.getSourceFile().fileName));
  for (let n = node, depth = 0; n && depth < 6; n = n.parent, depth++) {
    if (ts.isPropertyAccessExpression(n)) {
      if (declaredInSdk(checker.getSymbolAtLocation(n.name))) return true;
      const type = checker.getTypeAtLocation(n.expression);
      if (declaredInSdk(type.getSymbol()) || declaredInSdk(type.aliasSymbol)) return true;
    }
    if (ts.isCallExpression(n) || ts.isNewExpression(n)) {
      if (declaredInSdk(checker.getSymbolAtLocation(n.expression))) return true;
      const signature = checker.getResolvedSignature(n);
      if (signature?.declaration && inSdk(signature.declaration.getSourceFile().fileName)) return true;
    }
  }
  return false;
}

function nodeAt(sourceFile, position) {
  let found = sourceFile;
  const visit = (node) => {
    if (position >= node.getStart(sourceFile) && position < node.getEnd()) {
      found = node;
      ts.forEachChild(node, visit);
    }
  };
  ts.forEachChild(sourceFile, visit);
  return found;
}

const snippets = markdownFiles().flatMap(extractSnippets);
fs.rmSync(workDir, { recursive: true, force: true });
fs.mkdirSync(workDir, { recursive: true });
const byFile = new Map();
snippets.forEach((snippet, index) => {
  const { text, offset, importLines } = wrap(snippet);
  const name = path.join(workDir, `snippet${index}.${snippet.ext}`);
  fs.writeFileSync(name, text);
  byFile.set(name, { ...snippet, offset, importLines });
});

const program = ts.createProgram([...byFile.keys()], {
  target: ts.ScriptTarget.ES2022,
  module: ts.ModuleKind.ESNext,
  moduleResolution: ts.ModuleResolutionKind.Bundler,
  jsx: ts.JsxEmit.Preserve,
  allowJs: true,
  checkJs: true,
  noEmit: true,
  skipLibCheck: true,
  lib: ['lib.es2022.d.ts', 'lib.dom.d.ts'],
});
const checker = program.getTypeChecker();
const findings = [];
for (const [name, snippet] of byFile) {
  const sourceFile = program.getSourceFile(name);
  for (const diagnostic of program.getSemanticDiagnostics(sourceFile)) {
    if (diagnostic.start === undefined) continue;
    const node = nodeAt(sourceFile, diagnostic.start);
    // A missing foundry-js subpath (an invented '@crowdstrike/foundry-js/react') is SDK misuse too
    const badImport = diagnostic.code === 2307 && /['"]@crowdstrike\/foundry-js[^'"]*['"]/.test(node.getText(sourceFile));
    if (!badImport && !involvesSdk(checker, node)) continue;
    const { line } = sourceFile.getLineAndCharacterOfPosition(diagnostic.start);
    const mdLine = snippet.startLine + (line < snippet.importLines.length ? snippet.importLines[line] : line - snippet.offset);
    const message = ts.flattenDiagnosticMessageText(diagnostic.messageText, ' ');
    findings.push(`${path.relative(root, snippet.file)}:${mdLine}: ${message}`);
  }
}
fs.rmSync(workDir, { recursive: true, force: true });

console.log(`Checked ${snippets.length} snippets against @crowdstrike/foundry-js.`);
for (const finding of findings) console.log(finding);
process.exit(findings.length ? 1 : 0);
