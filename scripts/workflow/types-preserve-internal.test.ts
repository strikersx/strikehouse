import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

/**
 * Testes do types-preserve-internal.sh.
 *
 * Este script chegou a producao da ronda 1 com ZERO testes, e a ronda 2 da revisao por
 * pares mostrou porque e' que isso era perigoso: TODOS os modos de falha dele produziam
 * saida NAO-VAZIA, plausivel e ERRADA, com exit 0. O `[ -s "$tmp2" ]` de quem chama nao
 * apanhava nenhum — e o ficheiro que ele escreve e' versionado.
 *
 * Uma saida vazia e' um erro que se ve'. Uma saida plausivel e errada nao e'.
 */

const SCRIPT = path.resolve(__dirname, 'types-preserve-internal.sh');

let tmp: string;
beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tpi-'));
});
afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

const BLOCO = [
  '  // Allows to automatically instantiate createClient with right options',
  "  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)",
  '  __InternalSupabase: {',
  '    PostgrestVersion: "14.1"',
  '  }',
].join('\n');

/** Um types.ts como o `--linked` o gera (com bloco). */
function comBloco(schemas = ['graphql_public', 'public']) {
  return [
    'export type Json = string',
    '',
    'export type Database = {',
    BLOCO,
    ...schemas.map((s) => `  ${s}: {\n    Tables: {}\n  }`),
    '}',
    '',
    'type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">',
  ].join('\n');
}

/** Como o `--local` o gera (sem bloco, mas COM a referencia la' em baixo). */
function semBloco(schemas = ['graphql_public', 'public']) {
  return [
    'export type Json = string',
    '',
    'export type Database = {',
    ...schemas.map((s) => `  ${s}: {\n    Tables: {}\n  }`),
    '}',
    '',
    'type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">',
  ].join('\n');
}

function corre(novo: string, actual: string) {
  const fn = path.join(tmp, 'novo.ts');
  const fa = path.join(tmp, 'actual.ts');
  fs.writeFileSync(fn, novo);
  fs.writeFileSync(fa, actual);
  const stderr: string[] = [];
  let stdout = '';
  try {
    stdout = execFileSync('bash', [SCRIPT, fn, fa], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (e) {
    const err = e as { stderr?: string; status?: number };
    throw new Error(`saiu com ${err.status}\nstderr: ${err.stderr}`);
  }
  return { stdout, stderr: stderr.join('') };
}

describe('caminho feliz', () => {
  it('reinsere o bloco que o gerador local omite', () => {
    const { stdout } = corre(semBloco(), comBloco());
    expect(stdout).toContain('__InternalSupabase: {');
    expect(stdout).toContain('PostgrestVersion: "14.1"');
    // E no sitio certo: logo a seguir a abertura do Database, antes do 1o schema.
    expect(stdout.indexOf('__InternalSupabase: {')).toBeLessThan(stdout.indexOf('graphql_public'));
  });

  it('nao duplica quando o novo ja traz o bloco', () => {
    const { stdout } = corre(comBloco(), comBloco());
    expect(stdout.match(/^  __InternalSupabase: \{$/gm)?.length).toBe(1);
  });

  it('nao se deixa enganar pela REFERENCIA `Omit<Database, "__InternalSupabase">`', () => {
    // O ficheiro gerado contem sempre essa linha. Um `grep -q __InternalSupabase` solto
    // casava com ELA e o script concluia "o novo ja tem o bloco" — silenciosamente, sem
    // preservar nada. Foi o 1o defeito deste script, encontrado por testar a saida.
    expect(semBloco()).toContain('Omit<Database, "__InternalSupabase">');
    const { stdout } = corre(semBloco(), comBloco());
    expect(stdout).toContain('__InternalSupabase: {');
  });
});

describe('entradas patologicas — nunca corromper', () => {
  it('schema com DIGITO no nome nao faz a extraccao fugir', () => {
    // A regex original era `^  [a-zA-Z_]+: \{`, que NAO casa `v2_public:` — a extraccao
    // passava a fronteira e arrastava o schema inteiro para dentro do "bloco".
    const { stdout } = corre(semBloco(['v2_public', 'public']), comBloco(['v2_public', 'public']));
    // A assercao que conta: se a extraccao fugir, o schema inteiro entra no "bloco" e e'
    // REINSERIDO, portanto aparece DUAS vezes na saida. Uma 1a versao deste teste cortava
    // a saida no primeiro `v2_public` e por isso nunca via a duplicacao — passava com o
    // mutante. Contar ocorrencias ve' o que cortar escondia.
    expect(stdout.match(/^  v2_public: \{$/gm)?.length).toBe(1);
    expect(stdout.match(/^  public: \{$/gm)?.length).toBe(1);
    expect(stdout).toContain('__InternalSupabase: {');
  });

  it('actual TRUNCADO a meio do bloco nao produz TS invalido', () => {
    const truncado = comBloco().split('    PostgrestVersion')[0]; // corta dentro do bloco
    const { stdout } = corre(semBloco(), truncado);
    // A regra: em duvida, passa o NOVO intacto. Nunca inventar um bloco meio-feito.
    const abre = (stdout.match(/\{/g) ?? []).length;
    const fecha = (stdout.match(/\}/g) ?? []).length;
    expect(abre).toBe(fecha);
    expect(stdout).toBe(semBloco());
  });

  it('actual sem bloco nenhum passa o novo intacto', () => {
    const { stdout } = corre(semBloco(), semBloco());
    expect(stdout).toBe(semBloco());
  });

  it('actual inexistente passa o novo intacto', () => {
    const fn = path.join(tmp, 'n.ts');
    fs.writeFileSync(fn, semBloco());
    const out = execFileSync('bash', [SCRIPT, fn, path.join(tmp, 'nao-existe.ts')], {
      encoding: 'utf8',
    });
    expect(out).toBe(semBloco());
  });
});
