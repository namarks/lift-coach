/**
 * Reproduce prescription integrity findings at review source 696c1d34.
 * Run from the repository after npm ci, using Node with node:sqlite support:
 *   node docs/reviews/2026-09-app-review/evidence/prescription-write-repro.mjs
 *
 * Loads the unmodified service modules through in-memory TypeScript
 * transpilation. Applies every repository migration to a real, in-memory
 * SQLite database through Node's DatabaseSync. The small adapter reproduces
 * the D1 methods used by updateExercise; this is NOT a Workers/D1 integration
 * test. No network requests, persistent database, or filesystem writes occur.
 * Every account, plan, and slot is synthetic. A read barrier forces the two
 * writers to observe the same slot before either UPDATE executes.
 *
 * Expected at reviewed source: target_sets:'three'/target_rpe:99 persist,
 * and concurrent weight/cue patches both return success while the cue patch
 * restores the old weight. Assertions describe observed defects, not desired
 * behavior. Once repaired, move desired-state regression assertions into the
 * real Workers/D1 suite; failure here can mean the defects were fixed.
 */
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const sourceRequire = createRequire(path.join(root, 'package.json'));
const ts = sourceRequire('typescript');
const moduleCache = new Map();

function loadSource(file) {
  file = path.resolve(file);
  if (moduleCache.has(file)) return moduleCache.get(file).exports;
  const module = { exports: {} };
  moduleCache.set(file, module);
  const output = ts.transpileModule(readFileSync(file, 'utf8'), {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
  }).outputText;
  new Function('require', 'module', 'exports', output)(
    (id) => id.startsWith('.')
      ? loadSource(path.resolve(path.dirname(file), `${id}.ts`))
      : sourceRequire(id),
    module,
    module.exports,
  );
  return module.exports;
}

const service = loadSource(path.join(root, 'src/db.ts'));
const sqlite = new DatabaseSync(':memory:');
const migrationsPath = path.join(root, 'migrations');
for (const filename of readdirSync(migrationsPath).filter((name) => name.endsWith('.sql')).sort()) {
  sqlite.exec(readFileSync(path.join(migrationsPath, filename), 'utf8'));
}

let waitForBothLookups = false;
let reads = 0;
let releaseReaders;
const barrier = new Promise((resolve) => { releaseReaders = resolve; });
const db = {
  prepare(query) {
    let args = [];
    const parameters = () => Object.fromEntries(args.map((value, i) => [`?${i + 1}`, value]));
    return {
      bind(...values) { args = values; return this; },
      async first() {
        const result = sqlite.prepare(query).get(parameters()) ?? null;
        if (waitForBothLookups && query.includes('SELECT te.* FROM template_exercises')) {
          if (++reads === 2) releaseReaders();
          await barrier;
        }
        return result;
      },
      async all() { return { results: sqlite.prepare(query).all(parameters()) }; },
      async run() {
        const result = sqlite.prepare(query).run(parameters());
        return { meta: { changes: Number(result.changes) } };
      },
    };
  },
};

sqlite.exec(`
  INSERT INTO users(id,apple_sub,created_at)
    VALUES ('synthetic-user','synthetic-apple',1);
  INSERT INTO plans(id,user_id,name,created_at,updated_at)
    VALUES ('synthetic-plan','synthetic-user','Synthetic plan',1,1);
  INSERT INTO day_templates(id,plan_id,name,order_index,created_at,updated_at)
    VALUES ('synthetic-day','synthetic-plan','Synthetic day',0,1,1);
`);
const exercise = sqlite.prepare('SELECT id FROM exercises ORDER BY id LIMIT 1').get();
sqlite.prepare(`
  INSERT INTO template_exercises
    (id,day_template_id,exercise_id,order_index,target_sets,target_reps,
     target_weight,cues,created_at,updated_at)
  VALUES (?,?,?,?,?,?,?,?,?,?)
`).run('synthetic-slot', 'synthetic-day', exercise.id, 0, 3, 8, 100, 'Original cue', 1, 1);

try {
  const malformed = await service.updateExercise(
    db,
    'synthetic-user',
    { template_exercise_id: 'synthetic-slot' },
    { target_sets: 'three', target_rpe: 99 },
  );
  const poisoned = sqlite.prepare(`
    SELECT target_sets, typeof(target_sets) AS sets_type, target_rpe
      FROM template_exercises WHERE id=?
  `).get('synthetic-slot');
  assert.equal(malformed.target_sets, 'three');
  assert.equal(poisoned.target_sets, 'three');
  assert.equal(poisoned.sets_type, 'text');
  assert.equal(poisoned.target_rpe, 99);
  console.log(JSON.stringify({
    probe: 'malformed prescription',
    returned_target_sets: malformed.target_sets,
    stored: poisoned,
  }));

  sqlite.exec('UPDATE template_exercises SET target_sets=3, target_rpe=NULL');
  waitForBothLookups = true;
  const results = await Promise.all([
    service.updateExercise(db, 'synthetic-user', { template_exercise_id: 'synthetic-slot' }, { target_weight: 110 }),
    service.updateExercise(db, 'synthetic-user', { template_exercise_id: 'synthetic-slot' }, { cues: 'Updated cue' }),
  ]);
  const stored = sqlite.prepare(`
    SELECT target_weight, cues FROM template_exercises WHERE id=?
  `).get('synthetic-slot');
  assert.equal(results[0].target_weight, 110);
  assert.equal(results[1].cues, 'Updated cue');
  assert.equal(stored.target_weight, 100);
  assert.equal(stored.cues, 'Updated cue');
  console.log(JSON.stringify({
    probe: 'concurrent disjoint prescription patches',
    returned_weight: results[0].target_weight,
    returned_cue: results[1].cues,
    stored,
  }));
} finally {
  sqlite.close();
}
