import { useState } from "react";
import { useTranslation } from "react-i18next";
import { motion, AnimatePresence } from "framer-motion";
import { Loader2 } from "lucide-react";
import { useYogoPricing, type PricingItem, type PriceGroup } from "@/hooks/useYogoPricing";

function isMostPopular(item: PricingItem): boolean {
  const haystack = `${item.name} ${item.description ?? ""}`.toLowerCase();
  return haystack.includes("most popular");
}

// Short category label derived from plan shape. Rendered on every card so the
// card tops stay aligned across the row (popular badge floats above, in-flow).
function eyebrowLabel(item: PricingItem): string {
  if (item.type === "class_pass") {
    return item.numberOfClasses ? `${item.numberOfClasses} passes` : "Pacote de aulas";
  }
  if (item.isUnlimited) return "Ilimitado";
  if (item.classesPerWeek) return `${item.classesPerWeek}× por semana`;
  if (item.classesPerMonth) return `${item.classesPerMonth} passes`;
  return "Plano";
}

function periodLabel(item: PricingItem): string {
  if (item.type === "class_pass") {
    return item.numberOfClasses
      ? `/ ${item.numberOfClasses} ${item.numberOfClasses === 1 ? "aula" : "aulas"}`
      : "";
  }
  return "/ mês";
}

// Data-driven, scannable bullets — matches the red-dash list aesthetic.
function featureBullets(item: PricingItem, mainPrice: number): string[] {
  const out: string[] = [];
  if (item.type === "class_pass") {
    if (item.numberOfClasses)
      out.push(`${item.numberOfClasses} ${item.numberOfClasses === 1 ? "aula" : "aulas"}`);
    if (item.validDays) out.push(`Válido ${item.validDays} dias`);
  } else if (item.isUnlimited) {
    out.push("Aulas ilimitadas");
  } else if (item.classesPerWeek) {
    out.push(`${item.classesPerWeek} aulas / semana`);
  } else if (item.classesPerMonth) {
    out.push(`${item.classesPerMonth} aulas / mês`);
  }
  if (item.registrationFee > 0) out.push(`Inscrição: ${item.registrationFee}€`);
  const sessions = item.classesPerMonth ?? (item.classesPerWeek ? item.classesPerWeek * 4 : null);
  if (mainPrice && sessions) {
    const pps = (mainPrice / sessions).toFixed(2).replace(".", ",");
    out.push(`≈ ${pps}€ por aula`);
  }
  return out;
}

function PricingCard({ item }: { item: PricingItem }) {
  const { t } = useTranslation();
  const popular = isMostPopular(item);
  const hasMultipleOptions = item.paymentOptions.length > 1;
  const main = item.paymentOptions[0]; // cheapest (sorted ascending)
  const mainPrice = main?.price ?? 0;
  const trial = !popular && mainPrice === 0; // free-trial card (e.g. Experimental)

  const subtitle = item.description.replace(/\*?\s*most popular\s*/gi, "").trim();
  const bullets = trial
    ? ["Sem compromisso", ...featureBullets(item, mainPrice)]
    : featureBullets(item, mainPrice);

  const cardBase = "relative flex flex-col rounded-[2rem] border p-8 transition-all duration-500";
  const cardLook = popular
    ? "border-accent/70 bg-gradient-to-br from-accent/15 via-card to-card shadow-[0_30px_80px_-30px_hsl(var(--accent))] z-10"
    : trial
      ? "border-2 border-dashed border-accent bg-card shadow-[0_30px_80px_-40px_rgba(0,0,0,0.6)] hover:border-solid"
      : "border-border/60 bg-card shadow-[0_30px_80px_-40px_rgba(0,0,0,0.6)] hover:border-foreground/30";

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ duration: 0.3 }}
      className={`${cardBase} ${cardLook}`}
    >
      {/* Highlight badge — floats above, doesn't affect in-flow alignment */}
      {popular ? (
        <span className="absolute -top-3 left-8 rounded-full bg-accent px-4 py-1 font-mono text-[10px] uppercase tracking-[0.22em] text-accent-foreground shadow-[0_8px_24px_-8px_hsl(var(--accent))]">
          {t("pricing.mostPopular")}
        </span>
      ) : trial ? (
        <span className="absolute -top-3 left-8 rounded-full bg-foreground px-4 py-1 font-mono text-[10px] uppercase tracking-[0.22em] text-background shadow-[0_8px_24px_-8px_rgba(0,0,0,0.6)]">
          Grátis
        </span>
      ) : null}

      <div className="mb-4 font-mono text-[10px] uppercase tracking-[0.22em] text-muted-foreground">
        {eyebrowLabel(item)}
      </div>

      <h3 className="text-3xl font-semibold tracking-wider text-foreground">
        {item.name.replace(/⭐/g, "").replace(/- Most Popular/i, "").trim()}
      </h3>

      {subtitle && (
        <p className="mt-3 text-sm text-muted-foreground whitespace-pre-line">{subtitle}</p>
      )}

      {/* Price */}
      <div className="mt-8 flex items-baseline gap-2">
        {trial ? (
          <>
            <span className="text-5xl font-semibold tracking-tight text-foreground">Grátis</span>
            <span className="font-mono text-sm text-muted-foreground">{periodLabel(item)}</span>
          </>
        ) : (
          <>
            <span className="font-mono text-sm text-muted-foreground">€</span>
            <span className="text-6xl font-semibold tracking-tight text-foreground">{mainPrice}</span>
            <span className="font-mono text-sm text-muted-foreground">{periodLabel(item)}</span>
          </>
        )}
      </div>

      {/* Feature bullets */}
      {bullets.length > 0 && (
        <ul className="mt-8 space-y-3 border-t border-border/60 pt-6">
          {bullets.map((b, i) => (
            <li key={i} className="flex items-start gap-3 text-sm text-muted-foreground">
              <span className="mt-[0.6em] h-px w-4 shrink-0 bg-accent" />
              <span className="text-foreground/90">{b}</span>
            </li>
          ))}
        </ul>
      )}

      {/* CTA */}
      <div className="mt-auto pt-8 w-full">
        {!hasMultipleOptions ? (
          <a
            href={main.purchaseUrl}
            target="_blank"
            rel="noopener noreferrer"
            data-yogo-parsed="true"
            className={`flex items-center justify-between gap-4 rounded-full px-6 py-4 font-mono text-xs uppercase tracking-[0.22em] transition-all ${
              popular
                ? "bg-accent text-accent-foreground shadow-[0_12px_28px_-10px_hsl(var(--accent))] hover:opacity-90"
                : trial
                  ? "bg-foreground text-background hover:opacity-90"
                  : "border border-border/60 text-foreground hover:border-accent hover:text-accent"
            }`}
          >
            <span>{trial ? "Experimentar" : t("pricing.buy")}</span>
            <span aria-hidden>→</span>
          </a>
        ) : (
          <div className="space-y-2">
            {item.paymentOptions.map((opt) => (
              <a
                key={opt.id}
                href={opt.purchaseUrl}
                target="_blank"
                rel="noopener noreferrer"
                data-yogo-parsed="true"
                className={`flex items-center justify-between gap-4 rounded-full px-5 py-3 text-sm transition-all ${
                  popular
                    ? "border border-accent/60 text-foreground hover:bg-accent/10"
                    : "border border-border/60 text-foreground hover:border-accent hover:text-accent"
                }`}
              >
                <span className="uppercase tracking-wider">{opt.name || t("pricing.buy")}</span>
                <span className="font-semibold">{opt.price}€</span>
              </a>
            ))}
          </div>
        )}
      </div>
    </motion.div>
  );
}

function GroupTabs({
  groups,
  activeId,
  onSelect,
}: {
  groups: PriceGroup[];
  activeId: number;
  onSelect: (id: number) => void;
}) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-2 scrollbar-hide mb-10 justify-center flex-wrap">
      {groups.map((group) => (
        <button
          key={group.id}
          onClick={() => onSelect(group.id)}
          className={`px-5 py-2 rounded-full text-sm font-medium whitespace-nowrap transition-colors ${
            activeId === group.id
              ? "bg-foreground text-background"
              : "border border-border/60 text-muted-foreground hover:border-foreground/40 hover:text-foreground"
          }`}
        >
          {group.name}
        </button>
      ))}
    </div>
  );
}

export default function PricingSection() {
  const { data: priceGroups, isLoading, error } = useYogoPricing();
  const [activeGroupId, setActiveGroupId] = useState<number | null>(null);
  const { t } = useTranslation();

  const groups = priceGroups || [];
  const effectiveActiveId = activeGroupId ?? groups[0]?.id ?? 0;
  const activeGroup = groups.find((g) => g.id === effectiveActiveId);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-8 h-8 animate-spin text-accent" />
      </div>
    );
  }

  if (error || !groups.length) {
    return null;
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 30 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true }}
      transition={{ duration: 0.8, delay: 0.2 }}
    >
      {/* Tabs */}
      <GroupTabs
        groups={groups}
        activeId={effectiveActiveId}
        onSelect={setActiveGroupId}
      />

      {/* Cards */}
      <AnimatePresence mode="wait">
        {activeGroup && (
          <motion.div
            key={activeGroup.id}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: 0.25 }}
            className={`grid gap-6 items-stretch ${
              activeGroup.items.length === 1
                ? "grid-cols-1 max-w-sm mx-auto"
                : activeGroup.items.length === 2
                  ? "grid-cols-1 sm:grid-cols-2 max-w-2xl mx-auto"
                  : activeGroup.items.length <= 3
                    ? "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3"
                    : "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4"
            }`}
          >
            {activeGroup.items.map((item) => (
              <PricingCard key={`${item.type}-${item.id}`} item={item} />
            ))}
          </motion.div>
        )}
      </AnimatePresence>

      {/* Klarna note */}
      <p className="text-center text-sm text-muted-foreground mt-8">
        {t("pricing.noContracts")}
      </p>
    </motion.div>
  );
}
