const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {writeCompiledFile} = require('../scripts/build');

test('generated index output survives blocked truncation and failed replacement without losing prior contents', t => {
    const outDir = path.resolve(__dirname, '../../build/qa/2026-10-30-assistant-management-followup/compiler-writer-' + randomUUID());
    fs.mkdirSync(outDir, {recursive: true});
    const output = path.join(outDir, 'index.js');
    writeCompiledFile(outDir, output, 'original generated output');
    fs.utimesSync(output, new Date(0), new Date(0));
    writeCompiledFile(outDir, output, 'original generated output');
    assert.equal(fs.statSync(output).mtimeMs, 0);
    const nativeWrite = fs.writeFileSync;
    t.mock.method(fs, 'writeFileSync', (destination, ...args) => {
        if (path.resolve(destination) === output) throw Error('Simulated existing-file truncation refusal');
        return nativeWrite(destination, ...args);
    });
    writeCompiledFile(outDir, output, 'new generated output');
    assert.equal(fs.readFileSync(output, 'utf8'), 'new generated output');
    t.mock.method(fs, 'renameSync', () => { throw Error('Simulated replacement refusal'); });
    assert.throws(() => writeCompiledFile(outDir, output, 'incomplete output'), /replacement refusal/);
    assert.equal(fs.readFileSync(output, 'utf8'), 'new generated output');
    assert.deepEqual(fs.readdirSync(outDir), ['index.js']);
    assert.throws(() => writeCompiledFile(outDir, path.join(outDir, '..', 'outside.js'), 'outside'), /outside/);
    assert.equal(fs.existsSync(path.join(outDir, '..', 'outside.js')), false);
});
