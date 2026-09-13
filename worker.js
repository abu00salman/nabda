/**
 * نبضة — لوحة المتصدرين على Cloudflare Workers + KV
 * الربط المطلوب: KV Namespace باسم البايندنج  BOARD
 * المسارات:
 *   GET  /top            → أفضل 20 لاعبًا
 *   GET  /rank?score=123 → ترتيب هذه النتيجة
 *   POST /score          → { id, nick, score, level, streak }
 */
const ALLOWED = ['https://playnabda.com', 'https://www.playnabda.com', 'http://localhost:8080', 'http://127.0.0.1:8080'];
const NICK_RE = /^[a-zA-Z0-9_.-]{3,14}$/;
const ID_RE = /^p_[a-z0-9]{10,32}$/;
const MAX_SCORE = 100000, KEEP = 500, TOP = 20;

export default {
  async fetch(req, env) {
    const origin = req.headers.get('Origin') || '';
    const cors = {
      'Access-Control-Allow-Origin': ALLOWED.includes(origin) ? origin : ALLOWED[0],
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
    };
    const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: cors });
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });

    const url = new URL(req.url);
    const board = async () => (await env.BOARD.get('board', 'json')) || [];

    if (req.method === 'GET' && url.pathname === '/top') {
      const b = await board();
      return json(b.slice(0, TOP).map(({ id, nick, score, level }) => ({ id, nick, score, level })));
    }

    if (req.method === 'GET' && url.pathname === '/rank') {
      const score = parseInt(url.searchParams.get('score') || '0', 10);
      const b = await board();
      const higher = b.filter(x => x.score > score).length;
      return json({ rank: higher + 1, total: b.length });
    }

    if (req.method === 'POST' && url.pathname === '/score') {
      if (!ALLOWED.includes(origin)) return json({ error: 'forbidden' }, 403);
      let body; try { body = await req.json(); } catch { return json({ error: 'bad json' }, 400); }
      const { id, nick, level, streak } = body;
      const score = Number(body.score);
      if (!ID_RE.test(id || '')) return json({ error: 'bad id' }, 400);
      if (!NICK_RE.test(nick || '')) return json({ error: 'bad nick' }, 400);
      if (!Number.isInteger(score) || score < 0 || score > MAX_SCORE) return json({ error: 'bad score' }, 400);

      // حد معدل بسيط: كتابة واحدة كل 3 ثوانٍ لكل IP
      const ip = req.headers.get('CF-Connecting-IP') || 'x';
      if (await env.BOARD.get('rl:' + ip)) return json({ error: 'slow down' }, 429);
      await env.BOARD.put('rl:' + ip, '1', { expirationTtl: 3 });

      // منطقية النتيجة مقابل المستوى: كل مستوى = 5 إصابات، والإصابة القصوى ≈ 55 نقطة مع المضاعف
      const lvl = Math.max(1, Math.min(200, parseInt(level) || 1));
      if (score > lvl * 5 * 60 + 300) return json({ error: 'implausible' }, 400);

      let b = await board();
      const i = b.findIndex(x => x.id === id);
      const entry = { id, nick, score, level: lvl, streak: Math.max(0, Math.min(5000, parseInt(streak) || 0)), t: Date.now() };
      if (i >= 0) {
        if (b[i].score >= score) { b[i].nick = nick; }      // اسم جديد فقط، النتيجة لم تتحسن
        else b[i] = entry;
      } else b.push(entry);
      b.sort((x, y) => y.score - x.score || x.t - y.t);
      b = b.slice(0, KEEP);
      await env.BOARD.put('board', JSON.stringify(b));
      const rank = b.findIndex(x => x.id === id);
      return json({ ok: true, rank: rank >= 0 ? rank + 1 : null, total: b.length });
    }

    return json({ error: 'not found' }, 404);
  },
};
