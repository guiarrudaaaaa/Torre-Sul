import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const authorization = request.headers.get('Authorization');
    if (!authorization) return new Response(JSON.stringify({ error: 'Nao autenticado' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { global: { headers: { Authorization: authorization } } });
    const token = authorization.replace('Bearer ', '');
    const { data: sessionData } = await admin.auth.getUser(token);
    if (!sessionData.user) return new Response(JSON.stringify({ error: 'Sessao invalida' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    const { data: profile } = await admin.from('profiles').select('role').eq('id', sessionData.user.id).single();
    if (!profile || !['ADMINISTRADOR', 'COORDENADOR'].includes(profile.role)) return new Response(JSON.stringify({ error: 'Sem permissao' }), { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    const body = await request.json();
    if (!body.email || !body.password || !body.name || !body.role) return new Response(JSON.stringify({ error: 'Campos obrigatorios ausentes' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    const { data, error } = await admin.auth.admin.createUser({ email: body.email, password: body.password, email_confirm: true, user_metadata: { name: body.name } });
    if (error || !data.user) throw error || new Error('Usuario nao criado');
    const { error: profileError } = await admin.from('profiles').update({ name: body.name, role: body.role }).eq('id', data.user.id);
    if (profileError) throw profileError;
    return new Response(JSON.stringify({ id: data.user.id }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Erro interno' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
