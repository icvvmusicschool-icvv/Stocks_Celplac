// CELPLAC Estoque — gestão de usuários (somente administrador)
// Cria usuários e redefine senhas usando a chave de serviço, que nunca vai para o navegador.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const PAPEIS = ["ADMIN", "ENCARREGADO", "CONSULTA"];

function traduz(msg: string) {
  if (/already been registered|already exists/i.test(msg)) return "Já existe um usuário com este e-mail.";
  if (/password/i.test(msg)) return "Senha recusada: use pelo menos 8 caracteres.";
  if (/email/i.test(msg)) return "E-mail inválido.";
  return msg;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ erro: "Método não permitido." }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ erro: "Não autenticado." }, 401);

    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });

    // Quem está chamando precisa ser ADMIN ativo
    const { data: quem, error: errQuem } = await admin.auth.getUser(token);
    if (errQuem || !quem?.user) return json({ erro: "Sessão inválida. Entre novamente." }, 401);
    const { data: perfil } = await admin.from("perfis").select("papel, ativo").eq("id", quem.user.id).single();
    if (!perfil || !perfil.ativo || perfil.papel !== "ADMIN") {
      return json({ erro: "Somente o administrador pode gerenciar usuários." }, 403);
    }

    const body = await req.json().catch(() => ({}));

    if (body.acao === "criar") {
      const email = String(body.email || "").trim().toLowerCase();
      const senha = String(body.senha || "");
      const nome = String(body.nome || "").trim();
      const papel = String(body.papel || "");
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ erro: "E-mail inválido." }, 400);
      if (senha.length < 8) return json({ erro: "A senha precisa ter pelo menos 8 caracteres." }, 400);
      if (nome.length < 2) return json({ erro: "Informe o nome do usuário." }, 400);
      if (!PAPEIS.includes(papel)) return json({ erro: "Perfil inválido." }, 400);

      const { data, error } = await admin.auth.admin.createUser({
        email, password: senha, email_confirm: true, user_metadata: { nome },
      });
      if (error || !data?.user) return json({ erro: traduz(error?.message || "Falha ao criar usuário.") }, 400);

      const { error: errPerfil } = await admin.from("perfis")
        .update({ nome, papel, ativo: true }).eq("id", data.user.id);
      if (errPerfil) return json({ erro: "Usuário criado, mas falhou ao definir o perfil: " + errPerfil.message }, 500);

      return json({ ok: true, id: data.user.id });
    }

    if (body.acao === "redefinir_senha") {
      const id = String(body.id || "");
      const senha = String(body.senha || "");
      if (!id) return json({ erro: "Usuário não informado." }, 400);
      if (senha.length < 8) return json({ erro: "A senha precisa ter pelo menos 8 caracteres." }, 400);
      const { error } = await admin.auth.admin.updateUserById(id, { password: senha });
      if (error) return json({ erro: traduz(error.message) }, 400);
      return json({ ok: true });
    }

    return json({ erro: "Ação inválida." }, 400);
  } catch (e) {
    return json({ erro: "Erro interno: " + (e instanceof Error ? e.message : String(e)) }, 500);
  }
});
