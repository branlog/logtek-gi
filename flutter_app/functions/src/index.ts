import { onRequest } from 'firebase-functions/v2/https';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

initializeApp();

export const shopifyLogin = onRequest(async (req, res): Promise<void> => {
  try {
    if (req.method !== 'POST') {
      res.status(405).send('POST only');
      return;
    }

    const { email, password } =
      (req.body ?? {}) as { email?: string; password?: string };

    if (!email || !password) {
      res.status(400).json({ error: 'email et password sont requis.' });
      return;
    }

    // TODO: vérifier réellement dans Shopify ici

    const uid = `shopify:${email.toLowerCase()}`;
    const customToken = await getAuth().createCustomToken(uid, {
      provider: 'shopify',
      email,
    });

    res.status(200).json({ customToken });
    return;
  } catch (e: any) {
    res.status(500).json({ error: e?.message ?? String(e) });
    return;
  }
});

export const ping = onRequest((_req, res): void => {
  res.status(200).send('pong');
});
