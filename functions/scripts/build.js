'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const ts = require('typescript');

// Avoid Windows existing-file truncation failures. A failed replacement leaves
// prior output intact; unchanged files do not trigger emulator reloads.
function writeCompiledFile(outDir, fileName, contents) {
    const destination = path.resolve(fileName);
    const relative = path.relative(path.resolve(outDir), destination);
    if (relative === '..' || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) {
        throw Error('Compiler output is outside the configured output directory.');
    }
    try {
        if (fs.readFileSync(destination, 'utf8') === contents) return;
    } catch (error) {
        if (error.code !== 'ENOENT') throw error;
    }
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    const temporary = path.join(path.dirname(destination), `.${path.basename(destination)}.${randomUUID()}.tmp`);
    try {
        fs.writeFileSync(temporary, contents, {encoding: 'utf8', flag: 'wx'});
        fs.renameSync(temporary, destination);
    } finally {
        if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
    }
}

function build() {
    const configPath = path.resolve(__dirname, '../tsconfig.json');
    const config = ts.readConfigFile(configPath, ts.sys.readFile);
    const parsed = ts.parseJsonConfigFileContent(config.config ?? {}, ts.sys, path.dirname(configPath));
    const host = ts.createCompilerHost(parsed.options);
    host.writeFile = (fileName, data, bom, onError) => {
        try {
            writeCompiledFile(parsed.options.outDir, fileName, (bom ? '\uFEFF' : '') + data);
        } catch (error) {
            if (onError) onError(error.message);
            else throw error;
        }
    };
    const program = ts.createProgram(parsed.fileNames, parsed.options, host);
    const emitted = program.emit();
    const diagnostics = [
        ...(config.error ? [config.error] : []), ...parsed.errors,
        ...ts.getPreEmitDiagnostics(program), ...emitted.diagnostics,
    ];
    if (diagnostics.length) process.stderr.write(ts.formatDiagnostics(diagnostics, {
        getCurrentDirectory: () => process.cwd(), getCanonicalFileName: name => name, getNewLine: () => '\n',
    }));
    if (emitted.emitSkipped || diagnostics.some(diagnostic => diagnostic.category === ts.DiagnosticCategory.Error)) process.exitCode = 1;
}

module.exports = {writeCompiledFile};
if (require.main === module) build();
