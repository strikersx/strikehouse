import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

/**
 * Testes do supabase-worktree.sh — o provisionamento de uma stack Supabase por worktree.
 *
 * Nenhum destes levanta Docker. As duas costuras (`config` e `rewrite-env`) existem
 * precisamente para isso: um teste que precisasse de 12 containers nao se corre, e um
 * teste que nao se corre nao e' um teste.
 */

const SCRIPT = path.resolve(__dirname, 'supabase-worktree.sh');

let tmp: string;

/** Um worktree de mentira: o que o script precisa de encontrar, e nada mais. */
function fakeWorktree(opts: { deployScript?: string } = {}) {
  const wt = fs.mkdtempSync(path.join(tmp, 'wt-'));
  fs.mkdirSync(path.join(wt, 'supabase', 'migrations'), { recursive: true });
  fs.mkdirSync(path.join(wt, 'scripts'), { recursive: true });
  fs.writeFileSync(
    path.join(wt, 'scripts', 'deploy-edge-functions.sh'),
    opts.deployScript ??
      [
        '#!/usr/bin/env bash',
        'supabase functions deploy stripe-webhook --project-ref $P --no-verify-jwt',
        'supabase functions deploy create-checkout-session --project-ref $P',
        'supabase functions deploy list-payment-links --project-ref $P --no-verify-jwt',
      ].join('\n'),
  );
  return wt;
}

function run(args: string[], env: Record<string, string>) {
  try {
    return execFileSync('bash', [SCRIPT, ...args], {
      env: { ...process.env, ...env },
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (e) {
    // Sem isto, um script que morre da' "Command failed" e mais nada — e' preciso ir
    // reproduzir a mao para saber porque. O stderr e' a resposta; poe-se na mensagem.
    const err = e as { stderr?: string; stdout?: string; status?: number };
    throw new Error(
      `supabase-worktree.sh ${args.join(' ')} saiu com ${err.status}\n` +
        `stderr: ${err.stderr ?? '(vazio)'}\nstdout: ${err.stdout ?? '(vazio)'}`,
    );
  }
}

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'swt-'));
});
afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe('config derivado', () => {
  it('usa o slug como project_id — e' + ' nao o do config.toml do repo', () => {
    const wt = fakeWorktree();
    const cfgPath = run(['config'], {
      WORKTREE_DIR: wt,
      WORKTREE_SLUG: 'lane-alpha',
    }).trim();
    const cfg = fs.readFileSync(cfgPath, 'utf8');
    // O project_id nomeia os containers (supabase_db_<id>). Se nao for derivado, dois
    // worktrees colidem no mesmo conjunto de containers — o defeito que motivou tudo isto.
    expect(cfg).toContain('project_id = "lane-alpha"');
  });

  it('sanitiza um slug com barras, que o Supabase recusa como project_id', () => {
    const wt = fakeWorktree();
    const cfg = fs.readFileSync(
      run(['config'], { WORKTREE_DIR: wt, WORKTREE_SLUG: 'feat/sub/thing' }).trim(),
      'utf8',
    );
    expect(cfg).toContain('project_id = "feat-sub-thing"');
    // So' a linha do project_id: o resto do ficheiro tem barras legitimas (comentarios).
    expect(cfg.match(/^project_id = .*$/m)![0]).not.toContain('/');
  });

  it('desloca TODAS as portas pelo mesmo offset', () => {
    const wt = fakeWorktree();
    const cfg = fs.readFileSync(
      run(['config'], { WORKTREE_DIR: wt, WORKTREE_SLUG: 'p' }).trim(),
      'utf8',
    );
    const ports = [...cfg.matchAll(/^(?:shadow_)?port = (\d+)$/gm)].map((m) => Number(m[1]));
    expect(ports.length).toBeGreaterThanOrEqual(6);
    // Derivar so' o project_id nao chega: a 2a stack nascia com o nome certo e morria em
    // "Bind for 0.0.0.0:54322 failed: port is already allocated". Medido.
    expect(ports.every((p) => p >= 54420)).toBe(true);
  });

  it('reutiliza o offset de um config ja' + ' existente, para nao mover as portas debaixo de um .env ja' + ' escrito', () => {
    const wt = fakeWorktree();
    const env = { WORKTREE_DIR: wt, WORKTREE_SLUG: 'p' };
    const first = fs.readFileSync(run(['config'], env).trim(), 'utf8');
    const second = fs.readFileSync(run(['config'], env).trim(), 'utf8');
    const apiOf = (s: string) => s.match(/\[api\]\nport = (\d+)/)![1];
    expect(apiOf(second)).toBe(apiOf(first));
  });

  it('nao contem saida de comando injectada — o heredoc nao e' + ' citado', () => {
    const wt = fakeWorktree();
    const cfg = fs.readFileSync(
      run(['config'], { WORKTREE_DIR: wt, WORKTREE_SLUG: 'p' }).trim(),
      'utf8',
    );
    // O heredoc que gera isto NAO e' citado (precisa da expansao aritmetica das portas),
    // portanto um backtick ou $(...) num comentario e' EXECUTADO e a saida vai parar ao
    // ficheiro. Aconteceu: o banner do `supabase start` entrou aqui e o TOML morreu em
    // "invalid character at start of key". Os caracteres de desenho de caixa sao a
    // assinatura dessa saida.
    expect(cfg).not.toMatch(/[╭╰│├┬┴─]/);
    expect(cfg).not.toContain('http://127.0.0.1:54321');
  });
});

describe('funcoes sem verificacao de JWT', () => {
  it('le a lista do deploy script em vez de a ter hardcodada', () => {
    const wt = fakeWorktree();
    const cfg = fs.readFileSync(
      run(['config'], { WORKTREE_DIR: wt, WORKTREE_SLUG: 'p' }).trim(),
      'utf8',
    );
    expect(cfg).toContain('[functions.stripe-webhook]');
    expect(cfg).toContain('[functions.list-payment-links]');
    // Esta nao leva a flag no deploy script, logo NAO pode aparecer aqui: o local
    // passaria a testar uma politica de auth mais permissiva do que a de producao.
    expect(cfg).not.toContain('[functions.create-checkout-session]');
  });

  it('acompanha o deploy script quando ele muda', () => {
    // A prova de que e' lido e nao adivinhado: muda-se a fonte, muda-se o resultado.
    const wt = fakeWorktree({
      deployScript: 'supabase functions deploy uma-nova --project-ref $P --no-verify-jwt',
    });
    const cfg = fs.readFileSync(
      run(['config'], { WORKTREE_DIR: wt, WORKTREE_SLUG: 'p' }).trim(),
      'utf8',
    );
    expect(cfg).toContain('[functions.uma-nova]');
    expect(cfg).not.toContain('[functions.stripe-webhook]');
  });
});

describe('rewrite-env — o invariante caro', () => {
  /** Stub do `npx` no PATH: devolve as chaves sem levantar stack nenhuma. */
  function stubNpx(dir: string, api = 'http://127.0.0.1:54421') {
    const bin = path.join(dir, 'bin');
    fs.mkdirSync(bin, { recursive: true });
    fs.writeFileSync(
      path.join(bin, 'npx'),
      [
        '#!/usr/bin/env bash',
        `echo 'API_URL="${api}"'`,
        "echo 'PUBLISHABLE_KEY=\"sb_publishable_FAKE\"'",
        "echo 'SERVICE_ROLE_KEY=\"sb_secret_FAKE\"'",
      ].join('\n'),
      { mode: 0o755 },
    );
    return bin;
  }

  it('NAO escreve no .env do main quando o do worktree e' + ' um symlink para ele', () => {
    const main = fs.mkdtempSync(path.join(tmp, 'main-'));
    const wt = fakeWorktree();
    const mainEnv = path.join(main, '.env');
    fs.writeFileSync(mainEnv, 'VITE_SUPABASE_URL="https://remoto.supabase.co"\nSTRIPE_SECRET_KEY="sk_test_X"\n');
    // Exactamente o que o worktree-enter.sh faz aos ficheiros ignorados.
    fs.symlinkSync(mainEnv, path.join(wt, '.env'));
    const before = fs.readFileSync(mainEnv, 'utf8');

    run(['rewrite-env'], {
      WORKTREE_DIR: wt,
      WORKTREE_MAIN: main,
      WORKTREE_SLUG: 'p',
      PATH: `${stubNpx(tmp)}:${process.env.PATH}`,
    });

    // Este e' o teste todo: sem partir o symlink primeiro, isto reescrevia o .env do main
    // e o dos outros 5 worktrees — e o proximo a correr a suite batia na Supabase errada.
    expect(fs.readFileSync(mainEnv, 'utf8')).toBe(before);
    expect(fs.lstatSync(path.join(wt, '.env')).isSymbolicLink()).toBe(false);
  });

  it('aponta o .env do worktree ao local e preserva o que nao e' + ' Supabase', () => {
    const main = fs.mkdtempSync(path.join(tmp, 'main-'));
    const wt = fakeWorktree();
    fs.writeFileSync(
      path.join(main, '.env'),
      'VITE_SUPABASE_URL="https://remoto.supabase.co"\nSTRIPE_SECRET_KEY="sk_test_X"\nGITHUB_CI_TOKEN="gh_Y"\n',
    );
    fs.symlinkSync(path.join(main, '.env'), path.join(wt, '.env'));

    run(['rewrite-env'], {
      WORKTREE_DIR: wt,
      WORKTREE_MAIN: main,
      WORKTREE_SLUG: 'p',
      PATH: `${stubNpx(tmp)}:${process.env.PATH}`,
    });

    const out = fs.readFileSync(path.join(wt, '.env'), 'utf8');
    expect(out).toContain('VITE_SUPABASE_URL="http://127.0.0.1:54421"');
    expect(out).not.toContain('remoto.supabase.co');
    // Os segredos do Stripe nao sao locais: perde-los deixava as edge functions sem chave,
    // e o teste falharia por falta de segredo em vez de por JWT — dois erros parecidos.
    expect(out).toContain('STRIPE_SECRET_KEY="sk_test_X"');
    expect(out).toContain('GITHUB_CI_TOKEN="gh_Y"');
  });

  it('e' + ' idempotente: correr duas vezes nao duplica as chaves', () => {
    const main = fs.mkdtempSync(path.join(tmp, 'main-'));
    const wt = fakeWorktree();
    fs.writeFileSync(path.join(main, '.env'), 'VITE_SUPABASE_URL="https://remoto.supabase.co"\n');
    fs.symlinkSync(path.join(main, '.env'), path.join(wt, '.env'));
    const env = {
      WORKTREE_DIR: wt,
      WORKTREE_MAIN: main,
      WORKTREE_SLUG: 'p',
      PATH: `${stubNpx(tmp)}:${process.env.PATH}`,
    };
    run(['rewrite-env'], env);
    run(['rewrite-env'], env);
    const out = fs.readFileSync(path.join(wt, '.env'), 'utf8');
    expect(out.match(/^VITE_SUPABASE_URL=/gm)?.length).toBe(1);
  });
});
