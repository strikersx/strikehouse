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
    // Bases da CLI, por seccao. Verifica-se que TODAS sao deslocadas pelo MESMO offset —
    // nao apenas que sao "altas". Um mutante que somasse +1000 so' ao inbucket sobrevivia
    // a um `>= 54420`, e um que esquecesse o inspector_port nem sequer era olhado, porque
    // a regex antiga so' via `port`/`shadow_port`. Ambos apanhados pela revisao por pares.
    const bases: Record<string, number> = {
      api: 54321, db: 54322, shadow_port: 54320,
      studio: 54323, inbucket: 54324, analytics: 54327,
      inspector_port: 8083,
    };
    const sec = (name: string) => Number(cfg.match(new RegExp(`\\[${name}\\]\\nport = (\\d+)`))![1]);
    const offsets = [
      sec('api') - bases.api,
      sec('db') - bases.db,
      sec('studio') - bases.studio,
      sec('inbucket') - bases.inbucket,
      sec('analytics') - bases.analytics,
      Number(cfg.match(/^shadow_port = (\d+)$/m)![1]) - bases.shadow_port,
      Number(cfg.match(/^inspector_port = (\d+)$/m)![1]) - bases.inspector_port,
    ];
    expect(offsets.length).toBe(7);
    expect(new Set(offsets).size).toBe(1);   // um so' offset, para todas
    expect(offsets[0]).toBeGreaterThan(0);   // e deslocado de facto
  });

  it('reutiliza o offset REGISTADO, em vez de reescolher um livre', () => {
    const wt = fakeWorktree();
    const env = { WORKTREE_DIR: wt, WORKTREE_SLUG: 'p' };
    const cfgPath = run(['config'], env).trim();

    // Planta um offset que a escolha automatica NUNCA daria (ela comeca em +100 e sobe
    // pelo primeiro bloco livre). Comparar duas corridas seguidas nao testava nada: ambas
    // escolhiam o mesmo bloco livre e o mutante que apagava a reutilizacao sobrevivia.
    fs.writeFileSync(cfgPath, fs.readFileSync(cfgPath, 'utf8').replace(/^port = \d+$/m, 'port = 58321'));

    const depois = fs.readFileSync(run(['config'], env).trim(), 'utf8');
    expect(depois).toContain('port = 58321');          // api: +4000, reutilizado
    expect(depois).toMatch(/^port = 58322$/m);         // db seguiu o mesmo offset
  });

  it('nao contem saida de comando injectada — o heredoc nao e' + ' citado', () => {
    const wt = fakeWorktree();
    const cfg = fs.readFileSync(
      run(['config'], { WORKTREE_DIR: wt, WORKTREE_SLUG: 'p' }).trim(),
      'utf8',
    );
    // O heredoc que gera isto NAO e' citado (precisa da expansao aritmetica das portas),
    // portanto um backtick ou $(...) num comentario e' EXECUTADO e a saida vai parar ao
    // ficheiro. Aconteceu com o banner do `supabase start`.
    //
    // A 1a versao deste teste procurava caracteres de desenho de caixa — a assinatura
    // DESSE incidente, e nao a propriedade. Um `$(date)` ou `$(whoami)` num comentario
    // passava incolume. A revisao por pares apontou-o. Agora verifica-se a FORMA: cada
    // linha util e' `[seccao]` ou `chave = valor`. Qualquer saida de comando injectada
    // quebra isso, venha de onde vier.
    const mas = cfg
      .split('\n')
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith('#'))
      .filter((l) => !/^\[[a-z0-9_.-]+\]$/i.test(l))
      .filter((l) => !/^[A-Za-z_][A-Za-z0-9_]* = .+$/.test(l));
    expect(mas).toEqual([]);
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

describe('teardown — devolver o que se tomou [R26]', () => {
  function stubNpxOk(dir: string) {
    const bin = path.join(dir, 'bin');
    fs.mkdirSync(bin, { recursive: true });
    fs.writeFileSync(path.join(bin, 'npx'), '#!/usr/bin/env bash\nexit 0\n', { mode: 0o755 });
    return bin;
  }

  it('devolve o .env ao symlink do main', () => {
    const main = fs.mkdtempSync(path.join(tmp, 'main-'));
    const wt = fakeWorktree();
    fs.writeFileSync(path.join(main, '.env'), 'VITE_SUPABASE_URL="https://remoto.supabase.co"\n');
    // Estado a seguir a um provision: .env ja' e' ficheiro normal a apontar ao local.
    fs.writeFileSync(path.join(wt, '.env'), 'VITE_SUPABASE_URL="http://127.0.0.1:54421"\n');
    fs.mkdirSync(path.join(wt, '.supabase-wt', 'supabase'), { recursive: true });
    fs.writeFileSync(path.join(wt, '.supabase-wt', 'supabase', 'config.toml'), 'project_id = "p"\nport = 54421\n');

    run(['teardown'], {
      WORKTREE_DIR: wt, WORKTREE_MAIN: main, WORKTREE_SLUG: 'p',
      PATH: `${stubNpxOk(tmp)}:${process.env.PATH}`,
    });

    // Sem isto o .env fica a apontar para uma stack MORTA, e o travao do `make db-reset`
    // — que so' verifica se o alvo e' localhost — passa a AUTORIZAR um reset contra o nada.
    expect(fs.lstatSync(path.join(wt, '.env')).isSymbolicLink()).toBe(true);
    expect(fs.readFileSync(path.join(wt, '.env'), 'utf8')).toContain('remoto.supabase.co');
    expect(fs.existsSync(path.join(wt, '.supabase-wt'))).toBe(false);
  });

  it('usa o project_id REGISTADO, nao o slug recalculado', () => {
    const main = fs.mkdtempSync(path.join(tmp, 'main-'));
    const wt = fakeWorktree();
    fs.writeFileSync(path.join(main, '.env'), 'X=1\n');
    fs.mkdirSync(path.join(wt, '.supabase-wt', 'supabase'), { recursive: true });
    // O config regista um id que NAO corresponde ao slug passado — e' o desencontro real:
    // provision via `make db-local` usa hifens, o teardown do plugin usa underscores.
    fs.writeFileSync(path.join(wt, '.supabase-wt', 'supabase', 'config.toml'), 'project_id = "com-hifens"\nport = 54421\n');

    const bin = path.join(tmp, 'bin2');
    fs.mkdirSync(bin, { recursive: true });
    // Regista o project-id que lhe passaram, para podermos afirmar QUAL foi usado.
    fs.writeFileSync(path.join(bin, 'npx'),
      `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> ${JSON.stringify(path.join(tmp, 'chamadas.txt'))}\nexit 0\n`,
      { mode: 0o755 });

    run(['teardown'], {
      WORKTREE_DIR: wt, WORKTREE_MAIN: main, WORKTREE_SLUG: 'com_underscores',
      PATH: `${bin}:${process.env.PATH}`,
    });

    const chamadas = fs.readFileSync(path.join(tmp, 'chamadas.txt'), 'utf8');
    expect(chamadas).toContain('--project-id com-hifens');
    expect(chamadas).not.toContain('com_underscores');
  });
});

describe('teardown — ramo de FALHA', () => {
  /** npx que RECUSA parar a stack. */
  function stubNpxFalha(dir: string) {
    const bin = path.join(dir, 'binfail');
    fs.mkdirSync(bin, { recursive: true });
    fs.writeFileSync(path.join(bin, 'npx'), '#!/usr/bin/env bash\nexit 1\n', { mode: 0o755 });
    return bin;
  }

  it('NAO apaga o config derivado quando o stop falha', () => {
    const main = fs.mkdtempSync(path.join(tmp, 'main-'));
    const wt = fakeWorktree();
    fs.writeFileSync(path.join(main, '.env'), 'X=1\n');
    const derivado = path.join(wt, '.supabase-wt');
    fs.mkdirSync(path.join(derivado, 'supabase'), { recursive: true });
    fs.writeFileSync(path.join(derivado, 'supabase', 'config.toml'), 'project_id = "p"\nport = 54421\n');

    // O config e' o UNICO sitio que sabe o nome da stack. Apaga-lo com o stop falhado
    // transforma uma falha recuperavel em containers orfaos sem nome — o [R26] ao
    // contrario. Um mutante que movia o `rm -rf` para antes do `stop` ficava VERDE nos
    // 13 testes anteriores; este e' o teste que faltava.
    expect(() =>
      run(['teardown'], {
        WORKTREE_DIR: wt, WORKTREE_MAIN: main, WORKTREE_SLUG: 'p',
        PATH: `${stubNpxFalha(tmp)}:${process.env.PATH}`,
      }),
    ).toThrow();

    expect(fs.existsSync(path.join(derivado, 'supabase', 'config.toml'))).toBe(true);
  });

  it('recusa apagar quando o config nao tem project_id', () => {
    const wt = fakeWorktree();
    fs.mkdirSync(path.join(wt, '.supabase-wt', 'supabase'), { recursive: true });
    fs.writeFileSync(path.join(wt, '.supabase-wt', 'supabase', 'config.toml'), 'port = 54421\n');
    expect(() => run(['teardown'], { WORKTREE_DIR: wt, WORKTREE_SLUG: 'p' })).toThrow();
    expect(fs.existsSync(path.join(wt, '.supabase-wt'))).toBe(true);
  });
});

describe('propriedades do proprio script', () => {
  it('gera o config com heredoc CITADO, para que nada no corpo seja executado', () => {
    // Nao e' estilo: com <<TOML nao citado, todo o corpo — comentarios incluidos — sofre
    // expansao do shell. Um backtick num comentario correu `supabase start` e despejou o
    // banner para dentro do config. Testar a saida apanha o caso multi-linha; testar ISTO
    // nao deixa a classe nascer.
    // So' as linhas de codigo: os comentarios deste ficheiro FALAM do `<<TOML` antigo, e
    // uma regex solta sobre o ficheiro inteiro casava com a explicacao em vez do codigo.
    const aberturas = fs
      .readFileSync(SCRIPT, 'utf8')
      .split('\n')
      .filter((l) => !l.trim().startsWith('#'))
      .filter((l) => l.includes('<<'))
      .filter((l) => l.includes('TOML'));
    expect(aberturas.length).toBe(1);
    expect(aberturas[0]).toContain("<<'TOML'");
  });

  it("nao usa `sed -i ''`, que e' BSD-only e parte no CI Linux", () => {
    // O CI corre `npm run test:unit` em ubuntu-latest, e esse comando COLHE este ficheiro
    // (verificado com `vitest list`). O GNU sed le' o argumento vazio como NOME DE
    // FICHEIRO e sai 2 — 7 dos 13 testes falhavam em cada push. Nao estava vermelho so'
    // porque o `npm run lint` sai 1 antes e o job morre primeiro: cobertura zero
    // disfarcada de verde. Ronda 2 da revisao por pares.
    const codigo = fs
      .readFileSync(SCRIPT, 'utf8')
      .split('\n')
      .filter((l) => !l.trim().startsWith('#'));
    expect(codigo.filter((l) => /sed -i ''/.test(l))).toEqual([]);
  });
});
