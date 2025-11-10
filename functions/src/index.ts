import { onRequest } from 'firebase-functions/v2/https';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

// ⚠️ Utilise les Application Default Credentials en local
initializeApp({
  credential: applicationDefault(),
  projectId: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT,
});

// POST /shopifyLogin { email, password }
export const shopifyLogin = onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') return res.status(405).send('POST only');

    const { email, password } = (req.body ?? {}) as { email?: string; password?: string };
    if (!email || !password) return res.status(400).json({ error: 'email et password sont requis.' });

    // TODO: vérif Shopify ici
    const uid = `shopify:${email.toLowerCase()}`;
    const customToken = await getAuth().createCustomToken(uid, { provider: 'shopify', email });

    res.json({ customToken });
  } catch (e: any) {
    res.status(500).json({ error: e?.message ?? String(e) });
  }
});

export const ping = onRequest((_req, res) => res.status(200).send('pong'));

