/**
 * Logtek G&I — Firebase Functions (Express) starter
 * - /nlp/route: mappe une phrase → action JSON (Structured Outputs)
 * - /actions/execute: exécute l’action (TODO)
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const express = require('express');
const cors = require('cors');
const { z } = require('zod');
const OpenAI = require('openai');

admin.initializeApp();
const db = admin.firestore();

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

// -------- OpenAI setup --------
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

// -------- Zod schema for actions --------
const ActionEnum = z.enum([
  'CreateCompany',
  'CreateWarehouse',
  'CreateItem',
  'AdjustIn',
  'AdjustOut',
  'TransferStock'
]);

const ActionSchema = z.object({
  action: ActionEnum,
  payload: z.record(z.any())
});

// JSON Schema for structured outputs
const actionJsonSchema = {
  name: "inventory_action",
  schema: {
    type: "object",
    properties: {
      action: { type: "string", enum: ActionEnum.options },
      payload: { type: "object", additionalProperties: true }
    },
    required: ["action", "payload"],
    additionalProperties: false
  },
  strict: true
};

// -------- /nlp/route --------
app.post('/nlp/route', async (req, res) => {
  try {
    const { text, companyId } = req.body ?? {};
    if (!text || typeof text !== 'string') {
      return res.status(400).json({ error: 'text is required' });
    }

    const system = [
      "Tu es le routeur d’actions de Logtek G&I.",
      "Rends exactement un objet { action, payload } conforme au schéma.",
      "N’invente pas d’IDs. Utilise des noms si l’utilisateur n’a pas donné d’ID.",
      "Actions supportées: CreateCompany, CreateWarehouse, CreateItem, AdjustIn, AdjustOut, TransferStock.",
      companyId ? `Contexte: company_id=${companyId}` : ""
    ].filter(Boolean).join("\n");

    const completion = await openai.chat.completions.create({
      model: "gpt-4o-2024-08-06",
      messages: [
        { role: "system", content: system },
        { role: "user", content: text }
      ],
      response_format: {
        type: "json_schema",
        json_schema: actionJsonSchema
      }
    });

    const message = completion.choices?.[0]?.message?.content;
    if (!message) {
      return res.status(500).json({ error: 'No message from model' });
    }

    let parsed;
    try {
      parsed = JSON.parse(message);
      ActionSchema.parse(parsed);
    } catch (e) {
      return res.status(422).json({ error: 'Invalid structured output', details: String(e) });
    }

    return res.json(parsed);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Server error', details: String(err) });
  }
});

// -------- /actions/execute (squelette) --------
app.post('/actions/execute', async (req, res) => {
  try {
    const { action, payload, userUid } = req.body ?? {};
    ActionSchema.parse({ action, payload });

    // NOTE: Minimal MVP — only implement CreateCompany and CreateWarehouse
    if (action === 'CreateCompany') {
      const { name } = payload;
      if (!name) return res.status(400).json({ error: "name is required" });
      const companyRef = db.collection('companies').doc();
      const batch = db.batch();
      batch.set(companyRef, {
        name,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        owner_uid: userUid || null,
      });
      if (userUid) {
        batch.set(db.collection('memberships').doc(`${companyRef.id}_${userUid}`), {
          company_id: companyRef.id,
          user_uid: userUid,
          role: 'owner',
          created_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      const whRef = db.collection('warehouses').doc();
      batch.set(whRef, {
        company_id: companyRef.id,
        name: 'Principal',
        code: 'MAIN',
        active: true,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return res.json({ ok: true, company_id: companyRef.id });
    }

    if (action === 'CreateWarehouse') {
      const { company_id, name, code } = payload;
      if (!company_id || !name) return res.status(400).json({ error: "company_id and name are required" });
      const whRef = db.collection('warehouses').doc();
      await whRef.set({
        company_id, name, code: code || null, active: true,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return res.json({ ok: true, warehouse_id: whRef.id });
    }

    // TODO: implement other actions (CreateItem, AdjustIn, AdjustOut, TransferStock)
    return res.status(501).json({ error: "Not implemented", action });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'Server error', details: String(err) });
  }
});

exports.api = functions.https.onRequest(app);
