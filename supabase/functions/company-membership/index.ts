import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.0";

type JsonRecord = Record<string, unknown>;

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Missing Supabase environment variables.");
}

const VALID_ROLES = new Set(["owner", "admin", "employee", "viewer"]);

function response(
  status: number,
  payload: JsonRecord,
) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
    },
  });
}

function methodNotAllowed(): Response {
  return response(405, { error: "Method not allowed" });
}

serve(async (req) => {
  const url = new URL(req.url);
  const pathname = url.pathname;
  const routeParam = url.searchParams.get("route");

  if (req.method === "OPTIONS") {
    return response(204, { ok: true });
  }

  if (
    (pathname === "/invite" || routeParam == "invite") && req.method === "POST"
  ) {
    return await handleInvite(req);
  }

  if (
    (pathname === "/join-code" || routeParam == "join-code") &&
    req.method === "POST"
  ) {
    return await handleJoinCode(req);
  }

  return response(404, { error: "Not found" });
});

async function handleJoinCode(req: Request): Promise<Response> {
  try {
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
      return response(500, { error: "Supabase configuration missing" });
    }

    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return response(401, { error: "Missing authorization header" });
    }
    const accessToken = authHeader.replace("Bearer ", "");

    const supabase = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    });
    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: authUser, error: authError } = await supabase.auth.getUser();
    if (authError || !authUser?.user) {
      return response(401, { error: "Utilisateur non authentifié." });
    }
    const requester = authUser.user;

    const payload = await req.json().catch(() => null) as
      | { code?: string }
      | null;
    const code = payload?.code?.trim();
    if (!code) {
      return response(400, { error: "Code requis." });
    }

    const normalizedCode = code.toUpperCase();
    const codeHash = await hashCode(normalizedCode);

    const { data: joinCode, error: joinError } = await adminClient
      .from("company_join_codes")
      .select("id, company_id, role, uses, max_uses, expires_at, revoked_at")
      .eq("code_hash", codeHash)
      .is("revoked_at", null)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (joinError) {
      console.error("join-code lookup error", joinError);
      return response(500, { error: "Impossible de valider ce code." });
    }

    if (!joinCode) {
      return response(404, { error: "Code invalide ou expiré." });
    }

    if (joinCode.expires_at && new Date(joinCode.expires_at) <= new Date()) {
      return response(410, { error: "Ce code est expiré." });
    }

    if (joinCode.max_uses !== null && joinCode.max_uses !== undefined) {
      const uses = Number(joinCode.uses ?? 0);
      if (uses >= Number(joinCode.max_uses)) {
        return response(409, {
          error: "Ce code a déjà été utilisé au maximum.",
        });
      }
    }

    const nowIso = new Date().toISOString();
    const { data: membershipRow, error: membershipError } = await adminClient
      .from("memberships")
      .upsert(
        {
          company_id: joinCode.company_id,
          user_uid: requester.id,
          role: joinCode.role,
          updated_at: nowIso,
        },
        { onConflict: "company_id,user_uid" },
      )
      .select("id")
      .maybeSingle();

    if (membershipError) {
      console.error("join-code membership error", membershipError);
      return response(500, {
        error: "Impossible d’ajouter ce membre à l’entreprise.",
      });
    }

    const { error: updateError } = await adminClient
      .from("company_join_codes")
      .update({
        uses: Number(joinCode.uses ?? 0) + 1,
        updated_at: nowIso,
      })
      .eq("id", joinCode.id);

    if (updateError) {
      console.error("join-code update error", updateError);
    }

    return response(200, {
      companyId: joinCode.company_id,
      role: joinCode.role,
      membershipId: membershipRow?.id ?? null,
    });
  } catch (error) {
    console.error("join-code unexpected error", error);
    return response(500, { error: "Erreur inattendue." });
  }
}

async function hashCode(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function handleInvite(req: Request): Promise<Response> {
  try {
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
      return response(500, { error: "Supabase configuration missing" });
    }

    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return response(401, { error: "Missing authorization header" });
    }
    const accessToken = authHeader.replace("Bearer ", "");

    const supabase = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    });
    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: authUser, error: authError } = await supabase.auth.getUser();
    if (authError || !authUser?.user) {
      return response(401, { error: "Utilisateur non authentifié." });
    }
    const requester = authUser.user;

    const body = await req.json().catch(() => null) as {
      companyId?: string;
      email?: string;
      role?: string;
      notes?: string;
    } | null;

    if (!body?.companyId || !body?.email || !body?.role) {
      return response(400, {
        error: "Paramètres manquants.",
        detail: "companyId, email et role sont requis.",
      });
    }

    const companyId = body.companyId;
    const email = body.email.trim().toLowerCase();
    const role = body.role.trim().toLowerCase();
    if (!VALID_ROLES.has(role)) {
      return response(400, { error: "Rôle invalide." });
    }

    // Vérifie que le requester est owner/admin pour cette entreprise
    const { data: requesterMembership, error: membershipError } = await supabase
      .from("memberships")
      .select("role")
      .eq("company_id", companyId)
      .eq("user_uid", requester.id)
      .maybeSingle();

    if (membershipError) {
      console.error("membershipError", membershipError);
      return response(400, { error: "Impossible de valider les permissions." });
    }

    const requesterRole = requesterMembership?.role?.toString().toLowerCase();
    if (!requesterRole || !["owner", "admin"].includes(requesterRole)) {
      return response(403, {
        error: "Accès refusé. Rôle owner ou admin requis.",
      });
    }

    // Recherche utilisateur par email
    let targetUserId: string | null = null;
    let invitationStatus: "pending" | "accepted" = "pending";
    let alreadyRegistered = false;

    const userLookup = await adminClient.auth.admin.getUserByEmail(email).catch(
      () => null,
    );
    if (userLookup?.data?.user) {
      targetUserId = userLookup.data.user.id;
      alreadyRegistered = true;
      invitationStatus = "accepted";
    } else {
      const invited = await adminClient.auth.admin.inviteUserByEmail(email, {
        data: { invited_company_id: companyId, invited_role: role },
      }).catch((error) => {
        console.error("inviteUserByEmail error", error);
        return { data: null, error };
      });

      if (invited.error) {
        return response(400, {
          error: "Impossible d’inviter cet e-mail.",
          detail: invited.error.message ?? invited.error,
        });
      }
      targetUserId = invited.data?.user?.id ?? null;
      invitationStatus = "pending";
    }

    if (!targetUserId) {
      return response(500, {
        error: "Impossible de récupérer l’identifiant utilisateur.",
      });
    }

    const { data: membershipExists } = await adminClient
      .from("memberships")
      .select("id")
      .eq("company_id", companyId)
      .eq("user_uid", targetUserId)
      .maybeSingle();

    if (membershipExists) {
      return response(409, {
        error: "Cet utilisateur fait déjà partie de l’entreprise.",
      });
    }

    // Crée un enregistrement d’invitation
    const inviteToken = crypto.randomUUID();
    const { data: inviteRow, error: inviteError } = await adminClient
      .from("membership_invites")
      .insert({
        company_id: companyId,
        email,
        role,
        status: invitationStatus === "accepted" ? "accepted" : "pending",
        invite_token: inviteToken,
        user_uid: targetUserId,
        invited_by: requester.id,
        responded_at: invitationStatus === "accepted"
          ? new Date().toISOString()
          : null,
        notes: body.notes ?? null,
      })
      .select()
      .maybeSingle();

    if (inviteError || !inviteRow) {
      console.error("inviteError", inviteError);
      return response(500, { error: "Impossible d’enregistrer l’invitation." });
    }

    // Ajoute le membership immédiatement
    const { data: membershipRow, error: insertMembershipError } =
      await adminClient
        .from("memberships")
        .insert({
          company_id: companyId,
          user_uid: targetUserId,
          role,
        })
        .select("id")
        .maybeSingle();

    if (insertMembershipError) {
      console.error("insertMembershipError", insertMembershipError);
      return response(500, {
        error: "Invitation enregistrée, mais impossible d’ajouter le membre.",
      });
    }

    return response(200, {
      inviteId: inviteRow.id,
      membershipId: membershipRow?.id ?? null,
      alreadyRegistered,
      status: invitationStatus,
    });
  } catch (error) {
    console.error("Unexpected error", error);
    return response(500, { error: "Erreur inattendue." });
  }
}
