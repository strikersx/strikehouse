# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**BoxeMaster Pro** is a gym management system for boxing/MMA academies built with **Vite + React + TypeScript**. It prioritizes access control and financial tracking over class scheduling.

**Core Philosophy:**
- "Access-first" design: The system exists to answer "Can this person enter now?" and "How much came in/out today?"
- Financial truth: "If it doesn't create a transaction, it didn't happen"
- Simplicity for staff: Reception resolves everything in ≤3 clicks

**Stack:**
- Frontend: Vite + React 18 + TypeScript
- UI: shadcn/ui (Radix UI primitives) + Tailwind CSS
- Backend: Supabase (PostgreSQL + Auth + Edge Functions)
- State: TanStack Query (React Query)
- Routing: React Router v6
- i18n: i18next
- Payments: Stripe Checkout + Webhooks (100% online)

**⚠️ Important:** This is a **Vite project**, NOT Next.js. Don't suggest Next.js patterns.

---

## 📚 Documentation Structure

**CRITICAL: Read these documents before making changes:**

1. **`CLAUDE.md` (this file)** - Technical implementation guide
   - Architecture patterns
   - Code conventions
   - Common pitfalls

2. **`BUSINESS_FUNCTIONAL_SPEC.md`** (worktree: stupefied-galileo)
   - Business rules (100% non-technical)
   - Pricing model (plans, extras, discounts, promo codes)
   - PT interno & sublocação (revenue splits)
   - Use cases completos com exemplos
   - **READ THIS FIRST** for business logic questions

3. **`USE_CASES_TEST_CASES.md`** (worktree: stupefied-galileo)
   - 23 Use Cases detalhados (UC-001 a UC-023)
   - 20 Test Cases completos (TC-001 a TC-020)
   - Edge cases e cenários negativos
   - Test data fixtures e automation IDs
   - **USE THIS** for understanding user flows and test coverage

4. **`spec.md`** - Original spec (legacy, v1.7.1)
   - Database schema completo
   - Technical requirements (low-level)

5. **`PROJECT_PLAN.md`** - Implementation roadmap
   - Task checklist com status
   - Phases 1-11 breakdown

**When to read what:**
- **Implementing feature?** → Read BUSINESS_FUNCTIONAL_SPEC.md + relevant Use Cases
- **Writing tests?** → Read USE_CASES_TEST_CASES.md for Test Cases
- **Debugging?** → Check Use Cases for expected behavior
- **Schema question?** → Check spec.md for DB structure

---

## Development Commands

**⚠️ IMPORTANTE: SEMPRE usar Makefile para comandos comuns.**

```bash
# Ver todos os comandos disponíveis
make help

# Desenvolvimento
make dev              # Servidor de desenvolvimento (localhost:8080)
make build            # Build de produção
make lint             # Verificar linting
make lint-fix         # Corrigir linting automaticamente

# Testes
make test             # Testes unitários
make test-watch       # Testes em modo watch
make test-coverage    # Relatório de cobertura

# Base de dados (Supabase)
make db-push          # Aplicar migrações
make db-types         # Regenerar tipos TypeScript
make db-reset         # TRUNCA tabelas e apaga auth users — recusa alvo nao-local
make db-local         # Levantar stack Supabase LOCAL deste worktree
make db-local-stop    # Parar essa stack e devolver o .env ao main

# Deploy
make deploy           # Build + commit + push
make push-ci          # Push com token CI (para workflows GitHub)

# Limpeza
make clean            # Limpar cache e builds
```

**Não usar `npm run` diretamente** - o Makefile já encapsula tudo.

### ⚠️ Isolamento de base de dados por worktree

Sem `make db-local`, um worktree aponta para a Supabase **hospedada** — a mesma que todos
os outros worktrees. Até 2026-09-24 isso era sempre verdade, e `make db-reset` truncava
produção a partir de qualquer um deles.

Três alvos recusam agora correr contra um alvo não-local:

| Alvo | Escape, se for mesmo isso que queres |
|---|---|
| `make db-reset` | `FORCE_REMOTE_RESET=1` |
| `make test-integration` | `FORCE_REMOTE_TESTS=1` |
| `make test-e2e` | `FORCE_REMOTE_TESTS=1` |

O sinal é um só: `VITE_SUPABASE_URL` no `.env`. `make db-local` reescreve-o para
`localhost` (partindo o symlink para o `.env` do main) e `make db-local-stop` devolve-o.
Uma stack local custa 12 containers e ~1,5 GB, por isso levanta-se **a pedido**, não à
entrada do worktree.

Porquês e medições: `scripts/workflow/supabase-worktree.sh`.

## Architecture

### Role-Based Access System

The system has 4 user types with strict role-based routing:

**OWNER** - Investor with read-only financial visibility
- Routes: `/owner/*`
- Redirect after login: `/owner/dashboard`
- Access: Full visibility, audit logs, no operational control

**ADMIN** - Operational manager
- Routes: `/admin/*`
- Redirect after login: `/admin/dashboard`
- Access: Everything except owner-specific views
- All actions are logged in `audit_logs`

**STAFF** - Reception desk
- Routes: `/staff/*`
- Redirect after login: `/staff/checkin`
- Access: Check-in, payments, member creation, cash register

**PARTNER** - External coach renting space
- Routes: `/partner/*`
- Redirect after login: `/partner/dashboard`
- Access: Only their own rentals and credits

**Authentication Flow:**
- All auth handled by `src/hooks/useAuth.tsx` context provider (wraps entire app)
- After login, users redirect based on role via `getRedirectPath(role)`
- Protected routes use `<ProtectedRoute allowedRoles={['ADMIN', 'STAFF']}>` wrapper
- User data: `auth.users` table (Supabase Auth), staff metadata in `staff` table
- Auth state: `{ user, session, staff, staffId, isAuthenticated }`

### Check-in System (Core Feature)

The check-in flow is the heart of the application. Located in `src/hooks/useCheckin.ts`.

**Two types of check-ins:**
1. **MEMBER** - Gym members with QR codes (validates access, decrements credits)
2. **GUEST** - Students of external coaches (tied to active rentals, no validation)

**Member Check-in Validation Order (CRITICAL):**
```typescript
1. Member exists? → NOT_FOUND
2. Status = ATIVO? → BLOCKED (if BLOQUEADO/CANCELADO)
3. Has access_type? → EXPIRED (if LEAD)
4. Not expired? → EXPIRED (check access_expires_at)
5. If CREDITS: credits_remaining > 0? → NO_CREDITS
6. No exclusive rental blocking area? → AREA_EXCLUSIVE
   ↓
✅ ALLOWED → register check-in + decrement credits
```

**Access Types:**
- `SUBSCRIPTION` - Unlimited access for X days (30/90/365)
- `CREDITS` - Pay-per-visit (1 check-in = 1 credit, expires in 90 days)
- `DAILY_PASS` - Valid only on purchase day (until 23:59)

**Member Status Flow:**
```
LEAD → (first payment) → ATIVO → (expires) → BLOQUEADO
                                       ↓
                                  CANCELADO (manual, permanent)
```

**IMPORTANT: LEAD Status Display Pattern:**
LEAD members never had access (they're waiting for first payment). When displaying status:
- ✅ CORRECT: "Aguardando Primeiro Pagamento" / "Sem Acesso Ativo" (neutral state)
- ❌ INCORRECT: "Acesso Expirado" (implies access existed and expired)
- Use amber/yellow color for LEAD, red for actual errors (BLOQUEADO, CANCELADO, expired ATIVO)
- See `src/pages/MemberQR.tsx` `getStatusInfo()` for reference implementation

**Exclusive Area Blocking:**
When an external coach has an active rental on an `is_exclusive` area, member check-ins are BLOCKED during that time window. The check-in hook queries:
```sql
SELECT * FROM rentals
WHERE rental_date = TODAY
  AND status = 'SCHEDULED'
  AND areas.is_exclusive = true
  AND start_time <= NOW
  AND end_time >= NOW
```

### Database Schema Philosophy

**Key principles:**
- Every financial movement creates a `transactions` record (never delete, only adjust)
- Every check-in creates a `check_ins` record (immutable audit trail)
- Every admin action creates an `audit_logs` record
- All amounts stored in cents (INTEGER) to avoid float precision issues

**Critical tables:**
- `members` - Customer data + access control (`status`, `access_expires_at`, `credits_remaining`, `qr_code`)
- `check_ins` - Immutable log of all entry attempts (`type`: MEMBER|GUEST, `result`: ALLOWED|BLOCKED)
- `transactions` - All money in/out with category codes (`type`: RECEITA|DESPESA)
- `rentals` - Space sublet to external coaches (`status`: SCHEDULED|COMPLETED|CANCELLED)
- `staff` - Maps `auth.users` to roles and permissions
- `audit_logs` - Admin action history (OWNER-visible)
- `member_ibans` - Multiple IBANs per member for payment matching
- `cash_sessions` - Daily cash register state

**Schema location:** `supabase/migrations/20260110214515_*.sql`

### Supabase Integration Patterns

**Client location:** `src/integrations/supabase/client.ts`

**Always import the typed client:**
```typescript
import { supabase } from '@/integrations/supabase/client';
// Types auto-generated: src/integrations/supabase/types.ts
```

**Row Level Security (RLS):**
- All tables have RLS enabled
- Policies enforce role-based access at database level
- Staff can only see operational data
- Owner sees everything including audit logs
- Partner only sees their own rentals

**Common query patterns:**
```typescript
// Fetch with join
const { data } = await supabase
  .from('members')
  .select('*, member_ibans(*)')
  .eq('status', 'ATIVO');

// Insert with returning
const { data, error } = await supabase
  .from('transactions')
  .insert({ type: 'RECEITA', amount_cents: 6900, category: 'SUBSCRIPTION' })
  .select()
  .single();

// Update with conditions
await supabase
  .from('members')
  .update({ status: 'BLOQUEADO' })
  .eq('access_expires_at', '<', new Date().toISOString().split('T')[0]);
```

**Note:** There are no RPC functions for complex operations in the current implementation. Logic is handled client-side with proper RLS protection.

### Financial Transaction Model

**Every payment flow must:**
1. Create `transactions` record with category (`SUBSCRIPTION`, `CREDITS`, etc.)
2. Update member status/access (atomic with transaction)
3. Update `cash_sessions` if payment method is `DINHEIRO`
4. Create `audit_logs` entry (for admin actions)
5. (Future) Send WhatsApp notification

**Payment methods:**
- `DINHEIRO` - Cash (updates `cash_sessions.total_cash_in_cents`)
- `CARTAO` - Card via TPA machine
- `MBWAY` - Mobile payment (manual confirmation)
- `TRANSFERENCIA` - Bank transfer (requires admin verification + IBAN matching)

**Transaction categories (enum-like, in `categories` table):**
- Revenue: `SUBSCRIPTION`, `CREDITS`, `DAILY_PASS`, `RENTAL_FIXED`, `RENTAL_PERCENTAGE`, `PRODUTOS`
- Expenses: `FIXO_ALUGUEL`, `FIXO_UTILIDADES`, `VAR_COACHES`, `EQUIPAMENTOS`, etc.

**Example payment flow:**
```typescript
// 1. Create transaction
const { data: txn } = await supabase.from('transactions').insert({
  type: 'RECEITA',
  amount_cents: plan.preco_cents,
  payment_method: 'DINHEIRO',
  category: plan.tipo, // SUBSCRIPTION, CREDITS, DAILY_PASS
  member_id: memberId,
  created_by: staffId
}).select().single();

// 2. Update member access
await supabase.from('members').update({
  status: 'ATIVO',
  access_type: plan.tipo,
  access_expires_at: new Date(Date.now() + plan.duracao_dias * 86400000)
}).eq('id', memberId);

// 3. If cash, update session (find today's session first)
if (paymentMethod === 'DINHEIRO') {
  await supabase.from('cash_sessions')
    .update({ total_cash_in_cents: db.raw('total_cash_in_cents + ?', [plan.preco_cents]) })
    .eq('session_date', new Date().toISOString().split('T')[0]);
}
```

## Enrollment Fee System (Taxa de Matrícula)

### Overview

First-time members (status: LEAD) pay a one-time enrollment fee when activating their first plan.

### Key Concepts

**When charged:**
- Only for members with `status === 'LEAD'` (never been ATIVO)
- Renewals (BLOQUEADO → ATIVO) do NOT charge enrollment fee

**Configuration:**
- Stored per plan: `plans.enrollment_fee_cents` (INTEGER)
- Can be zero (no enrollment fee for that plan)
- Staff can override amount at enrollment time

**Transaction Structure:**
Creates TWO separate transaction records:
1. Plan payment (category: plan.tipo - SUBSCRIPTION/CREDITS/DAILY_PASS)
2. Enrollment fee (category: 'TAXA_MATRICULA')

### Implementation Pattern

**Route separation:**
- `/staff/enrollment` - For LEAD members (first-time enrollment)
- `/staff/payment` - For ATIVO/BLOQUEADO members (renewals)

**Enrollment page features:**
- Searches only `status = 'LEAD'` members
- Shows plan price + enrollment fee (editable)
- Calculates total = plan + adjusted fee
- Creates 2 transactions on instant payment
- For TRANSFERENCIA: creates pending_payment with reference `ENR-{timestamp}`

**Example code:**

```typescript
// Check if first-time enrollment
const isFirstTime = member.status === 'LEAD';

// Enrollment flow (instant payment)
if (isFirstTime && isInstantPayment) {
  // 1. Update member to ATIVO
  await supabase.from('members').update({
    status: 'ATIVO',
    access_type: plan.tipo,
    access_expires_at: newDate,
  }).eq('id', memberId);

  // 2. Transaction: Plan payment
  await supabase.from('transactions').insert({
    type: 'RECEITA',
    category: plan.tipo,
    amount_cents: plan.preco_cents,
    payment_method: 'DINHEIRO',
    member_id: memberId,
    description: `Plano: ${plan.nome}`,
    created_by: staffId,
  });

  // 3. Transaction: Enrollment fee (if > 0)
  if (enrollmentFeeCents > 0) {
    await supabase.from('transactions').insert({
      type: 'RECEITA',
      category: 'TAXA_MATRICULA',
      amount_cents: enrollmentFeeCents,
      payment_method: 'DINHEIRO',
      member_id: memberId,
      description: `Taxa de Matrícula - ${plan.nome}`,
      created_by: staffId,
    });
  }
}

// Enrollment via TRANSFERENCIA
else if (isFirstTime && method === 'TRANSFERENCIA') {
  const totalAmount = plan.preco_cents + enrollmentFeeCents;
  await supabase.from('pending_payments').insert({
    member_id: memberId,
    plan_id: plan.id,
    amount_cents: totalAmount,
    payment_method: 'TRANSFERENCIA',
    reference: `ENR-${Date.now()}`,  // ENR- prefix identifies enrollment
    expires_at: addDays(new Date(), 7),
    created_by: staffId,
  });
}
```

**Pending payment confirmation (Admin):**

When confirming a pending payment with reference `ENR-*`:

```typescript
const isEnrollment = payment.reference.startsWith('ENR-');

if (isEnrollment && plan) {
  // Split into 2 transactions
  const enrollmentFee = payment.amount_cents - plan.preco_cents;

  // Transaction 1: Plan
  await supabase.from('transactions').insert({
    category: plan.tipo,
    amount_cents: plan.preco_cents,
    ...
  });

  // Transaction 2: Fee (if > 0)
  if (enrollmentFee > 0) {
    await supabase.from('transactions').insert({
      category: 'TAXA_MATRICULA',
      amount_cents: enrollmentFee,
      ...
    });
  }
}
```

### Payment Page LEAD Detection

When staff selects a LEAD member in `/staff/payment`, show banner:

```tsx
{selectedMember.status === 'LEAD' && (
  <Alert className="border-yellow-500/50 bg-yellow-500/10">
    <AlertCircle className="h-4 w-4 text-yellow-500" />
    <AlertTitle>Novo Membro</AlertTitle>
    <AlertDescription>
      Este membro nunca foi ativado. Deseja matriculá-lo?
      <Button onClick={() => navigate('/staff/enrollment', { state: { member } })}>
        Ir para Matrícula →
      </Button>
    </AlertDescription>
  </Alert>
)}
```

### Handling Returning CANCELADO Members

Staff can manually decide whether to charge enrollment fee for returning CANCELADO members.

**In Payment page** ([src/pages/staff/Payment.tsx](src/pages/staff/Payment.tsx)):

When staff selects a CANCELADO member, show a decision banner:

```tsx
{selectedMember.status === 'CANCELADO' && (
  <Alert className="mt-3 border-blue-500/50 bg-blue-500/10">
    <AlertCircle className="h-4 w-4 text-blue-500" />
    <AlertTitle className="text-sm font-medium">Membro Cancelado</AlertTitle>
    <AlertDescription className="text-xs space-y-3">
      <p>Este membro já teve acesso cancelado. Deseja cobrar taxa de matrícula novamente?</p>
      <div className="flex gap-2">
        <Button
          size="sm"
          variant="outline"
          className="flex-1 border-accent text-accent hover:bg-accent/10"
          onClick={() => navigate('/staff/enrollment', { state: { member: selectedMember } })}
        >
          Sim - Com Taxa de Matrícula
        </Button>
        <Button
          size="sm"
          variant="outline"
          className="flex-1"
          onClick={() => {/* Continue normal flow - no enrollment fee */}}
        >
          Não - Apenas Plano
        </Button>
      </div>
    </AlertDescription>
  </Alert>
)}
```

**In Enrollment page** ([src/pages/staff/Enrollment.tsx](src/pages/staff/Enrollment.tsx)):

- Search accepts both LEAD and CANCELADO: `.in('status', ['LEAD', 'CANCELADO'])`
- Visual badges distinguish first-time vs returning members:
  - LEAD: Yellow badge "Novo"
  - CANCELADO: Blue badge "Retornando"
- TRANSFERENCIA reference prefix distinguishes enrollment type:
  - `ENR-{timestamp}` for LEAD (first-time enrollment)
  - `REA-{timestamp}` for CANCELADO (reactivation with fee)

```typescript
// Example: Conditional reference prefix
reference: selectedMember.status === 'LEAD'
  ? `ENR-${Date.now()}` // ENR = Enrollment (first-time)
  : `REA-${Date.now()}`, // REA = Reactivation (returning with fee)
```

**In PendingPayments confirmation** ([src/pages/admin/PendingPayments.tsx](src/pages/admin/PendingPayments.tsx)):

Detect both ENR- and REA- prefixes for transaction splitting:

```typescript
const isEnrollment = payment.reference.startsWith('ENR-');
const isReactivation = payment.reference.startsWith('REA-');
const hasEnrollmentFee = isEnrollment || isReactivation;

if (hasEnrollmentFee && plan) {
  // Split into 2 transactions
  const enrollmentFeeCents = payment.amount_cents - plan.preco_cents;

  // Transaction 1: Plan
  await supabase.from('transactions').insert({
    category: plan.tipo,
    amount_cents: plan.preco_cents,
    payment_method: 'TRANSFERENCIA',
    member_id: memberId,
    description: isEnrollment
      ? `Plano: ${plan.nome} (Matrícula)`
      : `Plano: ${plan.nome} (Reativação)`,
    created_by: staffId,
  });

  // Transaction 2: Enrollment fee (if > 0)
  if (enrollmentFeeCents > 0) {
    await supabase.from('transactions').insert({
      category: 'TAXA_MATRICULA',
      amount_cents: enrollmentFeeCents,
      payment_method: 'TRANSFERENCIA',
      member_id: memberId,
      description: isEnrollment
        ? `Taxa de Matrícula - ${plan.nome}`
        : `Taxa de Matrícula (Reativação) - ${plan.nome}`,
      created_by: staffId,
    });
  }
}
```

**Reference Prefix Convention:**
- `ENR-` = Enrollment (LEAD member, first-time)
- `REA-` = Reactivation (CANCELADO member returning with fee)
- `PAY-` = Payment (regular renewal without enrollment fee)

### Database Schema

```sql
-- Add to plans table
ALTER TABLE plans ADD COLUMN enrollment_fee_cents INTEGER DEFAULT 0 CHECK (enrollment_fee_cents >= 0);

-- Add category
INSERT INTO categories (code, nome, type) VALUES ('TAXA_MATRICULA', 'Taxa de Matrícula', 'RECEITA');
```

### Common Patterns

```typescript
// Format enrollment fee for display
const formatEnrollmentFee = (cents: number) => {
  return new Intl.NumberFormat('pt-PT', {
    style: 'currency',
    currency: 'EUR',
  }).format(cents / 100);
};

// Calculate total enrollment cost
const totalCost = plan.preco_cents + plan.enrollment_fee_cents;

// Check if member is eligible for enrollment
const canEnroll = member.status === 'LEAD';
```

### Reference

- Enrollment page: `src/pages/staff/Enrollment.tsx`
- Payment page: `src/pages/staff/Payment.tsx` (has LEAD detection banner)
- Plans admin: `src/pages/admin/Plans.tsx` (enrollment_fee field)
- Pending confirmations: `src/pages/admin/PendingPayments.tsx` (ENR- detection)

### Key Custom Hooks

**`useAuth()`** - Central authentication (`src/hooks/useAuth.tsx`)
- Provides: `user`, `session`, `staff`, `staffId`, `isAuthenticated`, `signIn()`, `signOut()`
- Fetches staff data on auth state change
- Handles role-based redirects via `getRedirectPath(role)`
- Wraps app in `<AuthProvider>` (see `src/App.tsx`)

**`useCheckin()`** - Check-in business logic (`src/hooks/useCheckin.ts`)
- `processQRCode(qrCode, staffId)` - Full QR scan flow
- `performCheckin(member, staffId)` - Execute check-in with validation
- `findMemberBySearch(query)` - Search by name or phone
- `validateAccess(member)` - Business rules validation
- `checkExclusiveAreaRental()` - Query for blocking rentals

**`useToast()`** - shadcn/ui toast notifications
- Used extensively for user feedback
- Import from `@/hooks/use-toast`
- Pattern: `toast({ title: 'Success', description: 'Check-in complete' })`

### Rental (Sublet) System

External coaches rent gym areas by time slot. Stored in `rentals` table.

**Fee models:**
- `FIXED` - Flat rate per slot (e.g., €30/hour stored in `external_coaches.fee_fixed_cents`)
- `PERCENTAGE` - % of base plan price (e.g., 40% stored in `external_coaches.fee_percentage`)

**Rental lifecycle:**
- Created as `SCHEDULED`
- After time passes → manually marked `COMPLETED`
- Can be `CANCELLED` (by coach or admin)

**Cancellation credit system:**
- If cancelled >48h before start → generates `coach_credits` record
- Credit valid for 90 days (`coach_credits.expires_at`)
- Credit can be applied to future rentals (`coach_credits.used_rental_id`)

**Exclusive areas (`areas.is_exclusive = true`):**
- When rental is active (SCHEDULED + current time within start/end)
- Member check-ins are BLOCKED (result: AREA_EXCLUSIVE)
- Staff sees message: "Área exclusiva ocupada até HH:MM"

### Component Patterns

**shadcn/ui components:** `src/components/ui/*`
- Pre-built: Button, Card, Dialog, Form, Input, Select, Tabs, etc.
- Always import from `@/components/ui/button` etc.
- Do NOT create custom components for things shadcn provides

**Custom components:**
- `QRScanner.tsx` - Uses html5-qrcode library for camera access
- `ProtectedRoute.tsx` - Role-based route guard wrapper
- `CheckinResultCard.tsx` - Visual feedback for check-in (green/red states)
- `LanguageSwitcher.tsx` - i18n language toggle

**Form handling pattern (react-hook-form + zod):**
```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import * as z from 'zod';

const formSchema = z.object({
  nome: z.string().min(1, 'Nome obrigatório'),
  telefone: z.string().min(9, 'Telefone inválido'),
});

const form = useForm<z.infer<typeof formSchema>>({
  resolver: zodResolver(formSchema),
  defaultValues: { nome: '', telefone: '' }
});
```

### QR Code System

**Format:** `MBR-XXXXXXXX` (8 random alphanumeric chars)
- Character set: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no I, O, 0, 1 to avoid confusion)
- Generated once at member creation, stored in `members.qr_code`
- UNIQUE constraint enforced at database level
- Never changes for the lifetime of the member

**Public QR page:**
- Route: `/m/:qrCode` (e.g., `/m/MBR-A1B2C3D4`)
- Accessible without login
- Displays QR code for member to save to phone/wallet
- Shows member name + plan status

**Check-in flow:**
1. Member shows QR on phone screen
2. Staff opens `/staff/checkin`
3. Staff scans QR with tablet camera (via `<QRScanner>` component)
4. System validates and shows result (ALLOWED/BLOCKED with reason)

### Cash Register (Caixa) Flow

Daily cash session tracking in `cash_sessions` table:

**Session lifecycle:**
1. Open: Staff enters `opening_balance_cents`
2. Throughout day: Cash transactions update `total_cash_in_cents` and `total_cash_out_cents`
3. Close: Staff enters `actual_closing_cents`
4. System calculates `difference_cents` (expected vs actual)
5. If `|difference| > 500` (€5.00): Alert admin

**Key constraint:** Sessions cannot be reopened once `status = 'CLOSED'`

**Query pattern:**
```typescript
const today = new Date().toISOString().split('T')[0];
const { data: session } = await supabase
  .from('cash_sessions')
  .select('*')
  .eq('session_date', today)
  .single();

// expected_closing_cents is GENERATED column:
// opening_balance_cents + total_cash_in_cents - total_cash_out_cents
```

## i18n Support

- Languages: Portuguese (pt) and English (en)
- Config: `src/i18n/config.ts`
- Translations: `src/i18n/locales/pt.ts` and `src/i18n/locales/en.ts`
- Hook: `useLanguage()` from `src/hooks/useLanguage.ts`
- Switcher: `<LanguageSwitcher />` component in header

## 🎯 Use Cases & Test Cases (Reference Guide)

**Location:** `USE_CASES_TEST_CASES.md` (worktree: stupefied-galileo)

### Quick Reference: Use Cases

**Matrícula & Pagamentos:**
- **UC-001:** Matrícula LEAD (primeira vez) → Taxa de matrícula obrigatória
- **UC-002:** Renovação BLOQUEADO → SEM taxa de matrícula
- **UC-003:** Reativação CANCELADO → Staff decide se cobra taxa
- **UC-004:** Upgrade com modalidades extras → Proration via Stripe
- **UC-005:** Aplicar código promocional → Validação local
- **UC-006:** Webhook Stripe bem-sucedido → Ativa aluno, cria transações
- **UC-007:** Webhook Stripe falhado → Retries automáticos
- **UC-008:** Cancelamento subscription → Mantém acesso até expiração

**Check-in & Controlo de Acesso:**
- **UC-009:** Check-in permitido → QR code válido, créditos disponíveis
- **UC-010:** Check-in bloqueado - Limite semanal → Planos 2x/3x
- **UC-011:** Check-in bloqueado - Modalidade não incluída → Sugere upgrade
- **UC-012:** Check-in bloqueado - Acesso expirado → Orienta renovação
- **UC-013:** Check-in bloqueado - Status CANCELADO → Orienta reativação
- **UC-014:** Reset automático de créditos → Rolling 7 days

**PT & Sublocação:**
- **UC-015:** Registar cliente de PT interno → Aluno paga plano + PT paga €200/mês
- **UC-016:** Propor exceção PT fee → Staff propõe, Admin aprova
- **UC-017:** Aprovar exceção PT fee → Admin/Owner aprova/rejeita
- **UC-018:** Registar aluno de professor externo → Split 50/50 padrão
- **UC-019:** Propor exceção sublocation split → Staff propõe ajuste
- **UC-020:** Aprovar exceção sublocation split → Admin/Owner decide

**Auditoria & Compliance:**
- **UC-021:** Visualizar audit logs → Apenas Owner (transparência total)
- **UC-022:** Rastrear transação Stripe → Admin debug end-to-end
- **UC-023:** Exportar relatório financeiro → PDF/Excel mensal

### Quick Reference: Test Cases

**Críticos (Phase 1 - Deploy Blocker):**
- **TC-001:** Matrícula LEAD com taxa → Stripe + webhook + 2 transactions
- **TC-009:** Check-in plano 2x permitido → Créditos decrementados
- **TC-010:** Check-in plano 2x bloqueado → Limite atingido, data de reset
- **TC-015:** Webhook duplicado → Idempotência garante no-op

**Importantes (Phase 2 - Pré-Production):**
- **TC-002:** Promo code válido → Desconto aplicado, times_used++
- **TC-011:** Modalidade não incluída → Bloqueio + sugestão upgrade
- **TC-016:** Pagamento falha 3x → Auto bloqueio
- **TC-003:** Renovação BLOQUEADO → SEM taxa

**Edge Cases (Phase 3 - Post-Launch):**
- **TC-020:** QR code colisão → Regeneração automática
- **TC-019:** Permissão negada → RLS bloqueia

### How to Use Use Cases

**Scenario 1: Implementing new feature**
```bash
# 1. Read business spec
cat BUSINESS_FUNCTIONAL_SPEC.md | grep "Taxa de Matrícula"

# 2. Find relevant Use Case
cat USE_CASES_TEST_CASES.md | grep "UC-001"

# 3. Understand flow, rules, edge cases
# 4. Implement based on Use Case steps
# 5. Write tests based on Test Cases
```

**Scenario 2: Debugging bug**
```bash
# User reports: "Pagamento não ativou aluno"
# → Check UC-006 (Webhook Stripe bem-sucedido)
# → Verify: Member status, transactions created, audit log
# → Check UC-022 (Rastrear transação) for debugging steps
```

**Scenario 3: Understanding business logic**
```bash
# Question: "BLOQUEADO paga taxa de matrícula?"
# → Read UC-002 (Renovação BLOQUEADO)
# → Answer: NÃO, renovação nunca cobra taxa
# → Compare with UC-003 (CANCELADO): Staff decide
```

---

## Edge Functions

**Location:** `supabase/functions/`

**Stripe Integration Functions:**
- `stripe-webhook/` - Processa webhooks do Stripe (UC-006)
  - Validates Stripe signature (security)
  - Idempotency check (via `stripe_events` table)
  - Handles: `checkout.session.completed`, `invoice.paid`, `invoice.payment_failed`, `customer.subscription.*`
  - Updates member status (LEAD → ATIVO)
  - Creates transactions (2 for enrollment, 1 for renewal)
  - Reads `weekly_limit`, `modalities_count` from Payment Link metadata
- `list-payment-links/` - Lista Payment Links activos do Stripe
  - Returns: id, url, metadata, price_cents
  - Used by SendPayment.tsx to show available links
- `create-offline-invoice/` - Cria invoice para pagamentos offline (DINHEIRO/CARTAO/MBWAY)
  - Creates `cash_transactions` entry
  - Updates `cash_sessions` totals
  - Activates member locally (no Stripe involvement)

**Subscription Management Functions:**
- `cancel-subscription/` - Cancela subscription no Stripe
- `pause-subscription/` - Pausa subscription no Stripe
- `update-subscription/` - Actualiza subscription (upgrade/downgrade)

**Utility Functions:**
- `seed-test-users/` - Creates test users for each role (OWNER, ADMIN, STAFF, PARTNER)
- `send-notification/` - WhatsApp integration (not implemented yet)
- `scheduled-jobs/` - Cron tasks for membership expiration and reminders (not implemented yet)

**To invoke locally (if Supabase CLI installed):**
```bash
supabase functions serve
curl -X POST http://localhost:54321/functions/v1/seed-test-users
```

### Deploying Edge Functions

**⚠️ IMPORTANTE: Sempre fazer deploy após modificar Edge Functions!**

```bash
# Login no Supabase (se não estiver logado)
supabase login

# ⚠️ CRÍTICO: Funções que recebem webhooks externos (Stripe) DEVEM usar --no-verify-jwt
# Caso contrário, o endpoint retorna 401 e os webhooks falham!

# Deploy de webhook (SEM JWT verification - recebe requests do Stripe)
supabase functions deploy stripe-webhook --project-ref cgdshqmqsqwgwpjfmesr --no-verify-jwt

# Deploy de funções que podem ser públicas
supabase functions deploy list-payment-links --project-ref cgdshqmqsqwgwpjfmesr --no-verify-jwt
supabase functions deploy create-offline-invoice --project-ref cgdshqmqsqwgwpjfmesr --no-verify-jwt

# Deploy de todas as funções (script - já inclui --no-verify-jwt)
./scripts/deploy-edge-functions.sh

# Ver logs de uma função
supabase functions logs stripe-webhook
```

**Secrets necessários (configurar no Supabase Dashboard → Edge Functions → Secrets):**
```
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...
```

**Troubleshooting:**
- Se webhooks não chegam → verificar `STRIPE_WEBHOOK_SECRET` matches entre `.env` e Supabase Dashboard
- Para resetar webhook secret: `npx tsx scripts/reset-webhook-secret.ts`
- Para verificar webhooks: `npx tsx scripts/test-webhook-delivery.ts`

## Common Pitfalls

**1. Don't bypass RLS**
Always use the `supabase` client. Never disable RLS or use service role key client-side.

**2. Money calculations**
Always work in cents (INTEGER). Only convert to euros for display: `(cents / 100).toFixed(2)`

**3. Check-in race conditions**
The `useCheckin` hook handles exclusive area checks before allowing entry. Don't skip this validation.

**4. Auth state timing**
User might be logged in (`user` exists) but `staff` record not yet loaded (race condition on first login). Always check `isAuthenticated` which ensures both exist.

**5. QR code format**
Must be uppercase, 8 chars, from allowed charset. Never use lowercase or confusing characters (I, O, 0, 1).

**6. Date handling**
Use ISO format `YYYY-MM-DD` for dates. Supabase stores as `DATE` type. Compare dates by converting to string:
```typescript
const today = new Date().toISOString().split('T')[0];
await supabase.from('members').select('*').eq('access_expires_at', today);
```

**7. Transaction categories**
Must match a `code` in `categories` table. System won't save without valid category.

## Project Status & Roadmap

Refer to `PROJECT_PLAN.md` for detailed task tracking and implementation phases.

**Current status (as of spec v1.7.1):**
- ✅ Phase 1-2: Infrastructure, auth, role-based routing
- ✅ Phase 3: Member CRUD, plans, basic check-in structure
- ⬜ Phase 3-4: QR scanner implementation, payment processing
- ⬜ Phase 5-8: Billing dashboard, rentals, financial reports, audit
- ⬜ Phase 9-11: Advanced dashboards, reports, polish

## Key Files Reference

- `spec.md` - Complete specification v1.7.1 (authoritative business rules)
- `PROJECT_PLAN.md` - Implementation phases and task checklist with status
- `src/App.tsx` - Route definitions and role-based access setup
- `src/hooks/useAuth.tsx` - Authentication context and role logic
- `src/hooks/useCheckin.ts` - Core check-in business logic
- `src/integrations/supabase/client.ts` - Supabase client instance
- `supabase/migrations/20260110214515_*.sql` - Complete database schema

## Domain-Specific Rules

**Member Status Transitions:**
- New member starts as `LEAD` (no access)
- First payment → `ATIVO`
- Access expires → auto-transition to `BLOQUEADO` (via cron job, not implemented yet)
- Manual cancellation → `CANCELADO` (permanent, cannot be reversed)

**Payment Confirmation (TRANSFERENCIA method):**
1. Staff creates `pending_payments` record
2. System sends IBAN + reference to member via WhatsApp (not implemented yet)
3. Member transfers money
4. Admin checks bank statement daily
5. Admin matches payment by IBAN (stored in `member_ibans`)
6. Admin confirms → creates transaction → activates access

**Rental Booking Rules:**
1. Cannot double-book same area at same time
2. If area is exclusive, only one rental allowed during that slot
3. Recurring rentals create multiple `rentals` records with same `series_id`
4. Cancellation generates credit only if >48 hours before start time
