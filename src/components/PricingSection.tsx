import { useState } from "react";
import { useTranslation } from "react-i18next";
import { motion, AnimatePresence } from "framer-motion";
import { Loader2 } from "lucide-react";
import { useYogoPricing, type PricingItem, type PriceGroup } from "@/hooks/useYogoPricing";

function isMostPopular(item: PricingItem): boolean {
  const haystack = `${item.name} ${item.description ?? ""}`.toLowerCase();
  return haystack.includes("most popular");
}

function getMonthlyPrice(item: PricingItem): number | null {
  if (item.type !== "membership") return null;
  const monthly = item.paymentOptions.find(
    (o) => o.name.toLowerCase().includes("mensal") || o.name.toLowerCase().includes("1 month")
  );
  return monthly?.price ?? item.paymentOptions[0]?.price ?? null;
}

function PricingCard({ item }: { item: PricingItem }) {
  const { t } = useTranslation();
  const hasMultipleOptions = item.paymentOptions.length > 1;
  const popular = isMostPopular(item);
  const monthlyPrice = getMonthlyPrice(item);
  const sessionsPerMonth = item.classesPerMonth ?? (item.classesPerWeek ? item.classesPerWeek * 4 : null);
  const pricePerSession = monthlyPrice && sessionsPerMonth ? (monthlyPrice / sessionsPerMonth).toFixed(2) : null;

  // For display: use the first (cheapest) option price for single-option cards
  const displayPrice = item.paymentOptions[0]?.price ?? 0;

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ duration: 0.3 }}
      className={`relative rounded-2xl flex flex-col overflow-hidden transition-all duration-300 ${
        popular
          ? "bg-white text-black border-2 border-white shadow-[0_0_30px_rgba(255,255,255,0.3),0_0_60px_rgba(255,255,255,0.15)] z-10"
          : "bg-white/[0.07] backdrop-blur-sm text-white border border-white/10"
      }`}
    >
      {/* Most Popular badge — slot reserved on every card so titles align */}
      <div className="flex justify-center pt-5">
        <span
          className={`text-xs font-semibold uppercase tracking-wider px-4 py-1.5 rounded-full ${
            popular ? "bg-gray-900 text-white" : "opacity-0 pointer-events-none"
          }`}
        >
          {t("pricing.mostPopular")}
        </span>
      </div>

      <div className="p-8 pb-6 flex flex-col flex-1 items-center text-center">
        {/* Name */}
        <h3 className={`text-2xl font-bold mb-4 ${popular ? "text-black" : "text-white"}`}>
          {item.name.replace(/⭐/g, "").replace(/- Most Popular/i, "").trim()}
        </h3>

        {/* Price */}
        <div className="mb-5">
          {!hasMultipleOptions ? (
            <>
              <span className={`text-5xl font-bold ${popular ? "text-black" : "text-white"}`}>
                {displayPrice}€
              </span>
              {item.type === "class_pass" && (
                <span className={`text-sm ml-1 ${popular ? "text-gray-500" : "text-white/50"}`}>
                  /{item.numberOfClasses} {t("pricing.classes")}
                </span>
              )}
            </>
          ) : (
            <>
              {monthlyPrice && (
                <span className={`text-5xl font-bold ${popular ? "text-black" : "text-white"}`}>
                  {monthlyPrice}€
                </span>
              )}
            </>
          )}
        </div>

        {/* Description (strip the "*Most Popular" marker since the badge already shows it) */}
        {item.description && (() => {
          const cleaned = item.description.replace(/\*?\s*most popular\s*/gi, "").trim();
          return cleaned ? (
            <p className={`text-sm whitespace-pre-line ${popular ? "text-gray-500" : "text-white/50"}`}>
              {cleaned}
            </p>
          ) : null;
        })()}

        {/* Registration fee */}
        {item.registrationFee > 0 && (
          <p className={`text-xs mt-2 ${popular ? "text-gray-400" : "text-white/40"}`}>
            + {t("pricing.registrationFee")}: {item.registrationFee}€
          </p>
        )}

        <div className="flex-1" />

        {/* CTA */}
        {!hasMultipleOptions ? (
          <a
            href={item.paymentOptions[0].purchaseUrl}
            target="_blank"
            rel="noopener noreferrer"
            data-yogo-parsed="true"
            className={`mt-6 block w-full text-center py-3 rounded-full text-sm font-semibold uppercase tracking-wider transition-all ${
              popular
                ? "bg-gray-900 text-white hover:bg-black"
                : "bg-transparent border border-white/30 text-white hover:bg-white/10"
            }`}
          >
            {t("pricing.buy")}
          </a>
        ) : (
          <div className="mt-6 w-full space-y-2">
            {item.paymentOptions.map((opt) => (
              <a
                key={opt.id}
                href={opt.purchaseUrl}
                target="_blank"
                rel="noopener noreferrer"
                data-yogo-parsed="true"
                className={`flex items-center justify-between w-full px-5 py-2.5 rounded-full text-sm transition-all ${
                  popular
                    ? "border border-gray-200 text-black hover:border-gray-900 hover:bg-gray-50"
                    : "border border-white/20 text-white hover:border-white/50 hover:bg-white/5"
                }`}
              >
                <span>{opt.name}</span>
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
              ? "bg-white text-black shadow-sm"
              : "bg-white/10 text-white/70 hover:bg-white/20"
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
        <Loader2 className="w-8 h-8 animate-spin text-red-600" />
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
            className={`grid gap-4 items-stretch ${
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
      <p className="text-center text-sm text-white/40 mt-8">
        {t("pricing.noContracts")}
      </p>
    </motion.div>
  );
}
