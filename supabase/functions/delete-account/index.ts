import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("SUPABASE_URL ou SERVICE_ROLE_KEY manquant.");
}

const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.replace("Bearer", "").trim();
    if (!jwt) {
      return new Response("Non authentifié.", { status: 401 });
    }

    // Use the provided JWT to resolve the current user.
    const supabaseUserClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false },
    });
    const {
      data: { user },
      error: userError,
    } = await supabaseUserClient.auth.getUser();
    if (userError || !user) {
      return new Response("Utilisateur introuvable.", { status: 401 });
    }

    const userId = user.id;
    const isIgnorableCleanupError = (code?: string, message?: string) => {
      // PGRST116: no rows deleted/updated. 42703: missing column. 42P01: missing table.
      if (code === "PGRST116" || code === "42703" || code === "42P01") {
        return true;
      }
      if (message?.toLowerCase().includes("column") &&
        message?.toLowerCase().includes("does not exist")) {
        return true;
      }
      if (message?.toLowerCase().includes("relation") &&
        message?.toLowerCase().includes("does not exist")) {
        return true;
      }
      return false;
    };

    // Remove direct user-owned rows first.
    const cleanupDeletes = [
      { table: "memberships", column: "user_uid" },
      { table: "membership_invites", column: "user_uid" },
      { table: "user_profiles", column: "user_uid" },
      { table: "user_notifications", column: "user_id" },
    ];
    const cleanupErrors: Array<{ step: string; error: unknown }> = [];

    for (const target of cleanupDeletes) {
      const { error } = await supabaseAdmin.from(target.table)
        .delete()
        .eq(target.column, userId);
      if (error && !isIgnorableCleanupError(error.code, error.message)) {
        console.error(`${target.table} delete`, error);
        cleanupErrors.push({ step: `${target.table}.delete`, error });
      }
    }

    // Null out creator/owner references that would otherwise block auth.users deletion.
    const cleanupNullifications = [
      { table: "membership_invites", column: "invited_by" },
      { table: "company_join_codes", column: "created_by" },
      { table: "inventory_sections", column: "created_by" },
      { table: "journal_entries", column: "created_by" },
    ];
    for (const target of cleanupNullifications) {
      const { error } = await supabaseAdmin.from(target.table)
        .update({ [target.column]: null })
        .eq(target.column, userId);
      if (error && !isIgnorableCleanupError(error.code, error.message)) {
        console.error(`${target.table} nullify ${target.column}`, error);
        cleanupErrors.push({ step: `${target.table}.nullify`, error });
      }
    }

    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(
      userId,
    );
    if (deleteError) {
      console.error(deleteError);
      return new Response(
        JSON.stringify({
          error: "Impossible de supprimer le compte.",
          detail: deleteError.message,
          cleanupErrors,
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    return new Response(
      JSON.stringify({ success: true, cleanupErrors }),
      { headers: { "Content-Type": "application/json" }, status: 200 },
    );
  } catch (error) {
    console.error(error);
    return new Response("Erreur inattendue.", { status: 500 });
  }
});
