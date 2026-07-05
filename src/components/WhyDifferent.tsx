import { useTranslation } from "react-i18next";
import { motion } from "framer-motion";
import { Button } from "@/components/ui/button";
import womenClassImg from "@/assets/muay-thai-women.jpg";

const WhyDifferent = () => {
  const { t } = useTranslation();

  const tags = [
    t("whyDifferent.tags.women", "Mulheres"),
    t("whyDifferent.tags.kids", "Kids 6+"),
    t("whyDifferent.tags.seniors", "55+"),
    t("whyDifferent.tags.beginners", "Iniciantes"),
  ];

  const scrollToTryNow = () => {
    const el = document.getElementById("try-now");
    el?.scrollIntoView({ behavior: "smooth" });
  };

  const scrollToBookNow = () => {
    const el = document.getElementById("horario");
    el?.scrollIntoView({ behavior: "smooth" });
  };

  return (
    <section className="relative bg-[#f5f3ef] text-foreground overflow-hidden">
      <div className="grid lg:grid-cols-[1fr_1.1fr] items-stretch min-h-[640px]">
        {/* LEFT — Copy */}
        <motion.div
          initial={{ opacity: 0, x: -30 }}
          whileInView={{ opacity: 1, x: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.8, ease: [0.25, 0.1, 0.25, 1] }}
          className="flex flex-col justify-center px-6 md:px-12 lg:px-16 py-16 lg:py-20"
        >
          <span className="text-red uppercase tracking-[0.25em] text-xs font-semibold mb-4">
            {t("whyDifferent.subtitle", "Porque é diferente")}
          </span>

          <h2 className="font-display text-3xl md:text-4xl lg:text-5xl font-light leading-[1.05] tracking-tight text-black mb-6">
            {t("whyDifferent.line1", "Ginásio de combate")}
            <br />
            {t("whyDifferent.line2", "não tem que ser")}
            <br />
            <span className="line-through text-neutral-400 font-light">
              {t("whyDifferent.lineStrike", "uma cave escura")}
            </span>
            .
          </h2>

          <div className="space-y-4 text-base md:text-lg text-neutral-700 leading-relaxed max-w-xl">
            <p>
              {t(
                "whyDifferent.p1",
                "A Striker's House nasceu com outra ideia. Um espaço com luz, com respeito, com pessoas que se cumprimentam pelo nome."
              )}
            </p>
            <p>
              <strong className="text-black">{t("whyDifferent.p2Lead", "Para todos.")}</strong>{" "}
              {t(
                "whyDifferent.p2",
                "Miúdos, seniores, mães que nunca treinaram, executivos, atletas a preparar competição, mulheres em aulas só para mulheres."
              )}
            </p>
            <p>
              <strong className="text-red">
                {t("whyDifferent.p3Lead", "Diversão primeiro.")}
              </strong>{" "}
              {t(
                "whyDifferent.p3",
                "A disciplina vem naturalmente quando o treino deixa de ser um castigo."
              )}
            </p>
          </div>

          <div className="mt-8 flex flex-col sm:flex-row gap-3">
            <Button
              size="lg"
              className="rounded-full text-sm tracking-[0.1em] font-bold bg-red-600 text-white hover:bg-red-700"
              onClick={scrollToTryNow}
            >
              {t("whyDifferent.ctaPrimary", "EXPERIMENTA GRÁTIS")}
            </Button>
            <Button
              size="lg"
              variant="outline"
              className="rounded-full text-sm tracking-[0.1em] font-semibold border-black text-black hover:border-accent hover:bg-accent hover:text-accent-foreground"
              onClick={scrollToBookNow}
            >
              {t("whyDifferent.ctaSecondary", "AULAS SÓ MULHERES")}
            </Button>
          </div>
        </motion.div>

        {/* RIGHT — Image + floating cards */}
        <motion.div
          initial={{ opacity: 0, scale: 1.04 }}
          whileInView={{ opacity: 1, scale: 1 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 1, ease: [0.25, 0.1, 0.25, 1] }}
          className="relative min-h-[400px] lg:min-h-full overflow-hidden"
        >
          <img
            src={womenClassImg}
            alt={t("whyDifferent.imageAlt", "Comunidade Striker's House")}
            className="w-full h-full object-cover"
            style={{ filter: "contrast(1.02) brightness(1.02)" }}
          />

          {/* Reviews badge */}
          <div className="absolute top-5 right-5 md:top-8 md:right-8 bg-white/95 backdrop-blur-sm rounded-lg px-4 py-3 shadow-lg max-w-[260px]">
            <div className="text-[10px] tracking-[0.2em] text-red font-bold">
              {t("whyDifferent.socialProof", "PROVA SOCIAL")}
            </div>
            <div className="text-base md:text-lg font-bold mt-0.5 text-black">
              {t("whyDifferent.rating", "5.0★ · 120+ reviews")}
            </div>
            <div className="text-xs text-neutral-500 mt-1 italic leading-snug">
              "{t(
                "whyDifferent.quote",
                "Ambiente onde me sinto em casa desde o dia 1"
              )}"
              {" — "}
              <span className="not-italic font-medium">Sofia</span>
            </div>
          </div>

          {/* Community tags */}
          <div className="absolute bottom-5 left-5 md:bottom-8 md:left-8 flex flex-wrap gap-2 max-w-[90%]">
            {tags.map((tag) => (
              <span
                key={tag}
                className="text-xs px-3 py-1.5 bg-white/95 backdrop-blur-sm rounded-full text-black font-semibold shadow-sm"
              >
                {tag}
              </span>
            ))}
          </div>
        </motion.div>
      </div>
    </section>
  );
};

export default WhyDifferent;
