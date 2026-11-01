// Explicit metadata-only migration. Never logs paths, URLs, tokens or patient data.
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const args = process.argv.slice(2);
const option = key => args[args.indexOf(key) + 1];
const projectId = option('--project');
if (projectId !== 'uhca-20800') throw Error('Explicit live UHC project required.');
if (Object.keys(process.env).some(key => key.endsWith('_EMULATOR_HOST') && process.env[key])) throw Error('Remove emulator configuration.');
const apply = args.includes('--apply');
async function main() {
    const cliAuth = require(path.join(option('--firebase-tools-root'), 'lib/auth.js'));
    const account = cliAuth.getProjectDefaultAccount(path.resolve(__dirname, '../..'));
    if (!account) throw Error('Firebase CLI login required.');
    const { OAuth2Client } = require('google-auth-library');
    const authClient = new OAuth2Client();
    authClient.refreshHandler = async () => {
        const token = await cliAuth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
        return { access_token: token.access_token, expiry_date: token.expires_at };
    };
    await authClient.getAccessToken();
    const { Storage } = require('@google-cloud/storage');
    const { Firestore } = require('@google-cloud/firestore');
    const bucket = new Storage({ projectId, authClient }).bucket('uhca-20800.firebasestorage.app');
    const db = new Firestore({ projectId, authClient });
    const [bucketInfo] = await bucket.getMetadata();
    const summary = { projectId, apply, versioning: bucketInfo.versioning?.enabled === true,
        generations: 0, tokenBearing: 0, revoked: 0, oldLinksRejected: 0, publicWithoutToken: 0, records: 0, urlsChanged: 0 };
    function bearerUrl(file, token, generation) {
        const url = new URL(`https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(file.name)}`);
        url.searchParams.set('alt', 'media');
        if (token) url.searchParams.set('token', token);
        if (generation) url.searchParams.set('generation', generation);
        return url;
    }
    async function head(url) {
        return (await fetch(url, { method: 'HEAD', redirect: 'manual', signal: AbortSignal.timeout(30000) })).status;
    }
    async function revoke(file, metadata) {
        const tokens = String(metadata.metadata?.firebaseStorageDownloadTokens || '').split(',').filter(Boolean);
        if (!tokens.length) return;
        summary.tokenBearing++;
        if (!apply) return;
        await file.setMetadata({ cacheControl: 'private, no-store, max-age=0',
            metadata: { firebaseStorageDownloadTokens: null } }, { ifMetagenerationMatch: metadata.metageneration });
        const [fresh] = await file.getMetadata();
        if (fresh.metadata?.firebaseStorageDownloadTokens || fresh.generation !== metadata.generation || fresh.md5Hash !== metadata.md5Hash) {
            throw Error('Metadata revocation or byte preservation verification failed.');
        }
        summary.revoked++;
        for (const token of tokens) {
            for (const generation of [undefined, metadata.generation]) {
                const status = await head(bearerUrl(file, token, generation));
                if (![401, 403, 404].includes(status)) throw Error('An old link remains accessible.');
            }
            summary.oldLinksRejected++;
        }
    }
    if (args.includes('--canary')) {
        if (!apply) throw Error('Canary needs explicit --apply.');
        const file = bucket.file(`medical_documents/qa-revocation-${randomUUID()}/self/synthetic.txt`);
        const token = randomUUID();
        try {
            await file.save(Buffer.from('Synthetic token revocation check. No patient data.'), { resumable: false,
                metadata: { contentType: 'text/plain', cacheControl: 'no-store', metadata: { firebaseStorageDownloadTokens: token } } });
            const [metadata] = await file.getMetadata();
            if (await head(bearerUrl(file, token)) !== 200) throw Error('Canary old-link control failed.');
            await revoke(file, metadata);
            if (![401, 403, 404].includes(await head(bearerUrl(file)))) throw Error('Anonymous access remains.');
            console.log(JSON.stringify({ projectId, canary: 'passed', oldLinkBefore: 200, oldLinkAfter: 'denied', bytesUnchanged: true }));
        } finally { await file.delete({ ignoreNotFound: true }); await db.terminate(); }
        return;
    }
    for (const prefix of ['medical_documents/', 'medical_document_replacement_files/']) {
        let query = { prefix, versions: true, autoPaginate: false, maxResults: 100 };
        do {
            const [files, next] = await bucket.getFiles(query);
            for (const file of files) {
                const [metadata] = await file.getMetadata();
                summary.generations++;
                if (await head(bearerUrl(file, null, metadata.generation)) === 200) summary.publicWithoutToken++;
                await revoke(file, metadata);
            }
            query = next;
        } while (query);
    }
    if (summary.publicWithoutToken) throw Error('Medical objects have anonymous access without a token.');
    const documents = await db.collection('medical_documents').get();
    for (const doc of documents.docs) {
        summary.records++;
        const url = `https://us-central1-${projectId}.cloudfunctions.net/readMedicalDocument?documentId=${encodeURIComponent(doc.id)}`;
        if (doc.data().url === url) continue;
        summary.urlsChanged++;
        if (apply) await db.runTransaction(async tx => {
            const current = await tx.get(doc.ref);
            if (current.exists) tx.update(doc.ref, { url });
        });
    }
    console.log(JSON.stringify(summary));
    await db.terminate();
}
main().catch(error => {
    console.error(JSON.stringify({ error: 'Medical token revocation failed', code: error.code || error.name }));
    process.exitCode = 1;
});
