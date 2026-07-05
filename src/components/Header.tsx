import { useState, useEffect, useRef } from "react";
import { useTranslation } from "react-i18next";
import { Link, useLocation } from "react-router-dom";
import { X, Menu, ChevronDown } from "lucide-react";
import LanguageSwitcher from "./LanguageSwitcher";

const Header = () => {
  const { t } = useTranslation();
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [isExperienceOpen, setIsExperienceOpen] = useState(false);
  const [isMobileExperienceOpen, setIsMobileExperienceOpen] = useState(false);
  const location = useLocation();
  const isHomePage = location.pathname === "/";
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Prevent body scroll when menu is open
  useEffect(() => {
    if (isMenuOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = 'unset';
    }
    return () => {
      document.body.style.overflow = 'unset';
    };
  }, [isMenuOpen]);

  // Cleanup timeout on unmount
  useEffect(() => {
    return () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, []);

  const handleMouseEnter = () => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    setIsExperienceOpen(true);
  };

  const handleMouseLeave = () => {
    timeoutRef.current = setTimeout(() => setIsExperienceOpen(false), 150);
  };

  const handleLinkClick = () => {
    setIsMenuOpen(false);
    setIsMobileExperienceOpen(false);
  };

  // Dropdown sub-items
  const experienceItems = [
    {
      href: isHomePage ? "#modalities" : "/#modalities",
      label: t('header.experienceModalities'),
      isAnchor: isHomePage,
    },
    {
      href: isHomePage ? "#horario" : "/#horario",
      label: t('header.schedule'),
      isAnchor: isHomePage,
    },
    {
      href: "https://apps.apple.com/dk/app/strikers-house/id6760544356",
      label: t('header.downloadApp'),
      isAnchor: true,
    },
  ];

  const SmartLink = ({ href, isAnchor, onClick, className, children }: {
    href: string; isAnchor: boolean; onClick?: () => void; className?: string; children: React.ReactNode;
  }) => isAnchor ? (
    <a href={href} onClick={onClick} className={className}>{children}</a>
  ) : (
    <Link to={href} onClick={onClick} className={className}>{children}</Link>
  );

  return (
    <>
      <header className="fixed top-0 left-0 right-0 z-50 bg-background/95 backdrop-blur-sm pt-safe">
        <div className="container mx-auto px-4 lg:px-8 py-3 lg:py-4">
          <nav className="flex items-center justify-between gap-4">
            {/* Logo */}
            <Link to="/" className="text-sm tracking-[0.3em] uppercase font-light shrink-0">
              Striker's House
            </Link>

            {/* Desktop Navigation — center nav items */}
            <ul className="hidden lg:flex items-center gap-6 xl:gap-8">
              {/* Experiência dropdown */}
              <li
                className="relative"
                onMouseEnter={handleMouseEnter}
                onMouseLeave={handleMouseLeave}
              >
                <button className="flex items-center gap-1 text-xs uppercase tracking-[0.15em] text-foreground/80 hover:text-foreground transition-colors py-2">
                  {t('header.experience')}
                  <ChevronDown className={`w-3 h-3 transition-transform duration-200 ${isExperienceOpen ? 'rotate-180' : ''}`} />
                </button>
                {isExperienceOpen && (
                  <div className="absolute top-full left-0 mt-1 min-w-[180px] bg-background/95 backdrop-blur-sm border border-border py-2 shadow-lg">
                    {experienceItems.map((item) => (
                      <SmartLink
                        key={item.href}
                        href={item.href}
                        isAnchor={item.isAnchor}
                        onClick={() => setIsExperienceOpen(false)}
                        className="block px-4 py-2.5 text-xs uppercase tracking-[0.12em] text-muted-foreground hover:text-foreground hover:bg-muted/20 transition-colors"
                      >
                        {item.label}
                      </SmartLink>
                    ))}
                  </div>
                )}
              </li>

              {/* Unidades dropdown */}
              <li className="relative group">
                <button className="flex items-center gap-1 text-xs uppercase tracking-[0.15em] text-foreground/80 hover:text-foreground transition-colors py-2">
                  {t('header.locations')}
                  <ChevronDown className="w-3 h-3" />
                </button>
                <div className="absolute top-full left-0 mt-1 min-w-[180px] bg-background/95 backdrop-blur-sm border border-border py-2 shadow-lg hidden group-hover:block">
                  <a
                    href="#contact"
                    className="block px-4 py-2.5 text-xs uppercase tracking-[0.12em] text-muted-foreground hover:text-foreground hover:bg-muted/20 transition-colors"
                  >
                    Carcavelos
                  </a>
                </div>
              </li>

              {/* Comunidade */}
              <li>
                <Link to="/comunidade" className="text-xs uppercase tracking-[0.15em] text-foreground/80 hover:text-foreground transition-colors py-2">
                  {t('header.community')}
                </Link>
              </li>

              {/* Corporate */}
              <li>
                <Link to="/corporate" className="text-xs uppercase tracking-[0.15em] text-foreground/80 hover:text-foreground transition-colors py-2">
                  {t('header.corporate')}
                </Link>
              </li>
            </ul>

            {/* Desktop CTAs + Language + Login */}
            <div className="hidden lg:flex items-center gap-3">
              {/* RESERVAR AGORA — outlined, rounded */}
              <SmartLink
                href={isHomePage ? "#horario" : "/#horario"}
                isAnchor={isHomePage}
                className="hidden xl:inline-flex px-5 py-2 border border-foreground/30 rounded-full text-[10px] uppercase tracking-[0.15em] text-foreground hover:border-accent hover:text-accent transition-colors"
              >
                {t('header.bookNow')}
              </SmartLink>

              {/* COMPRAR SESSÕES — outlined, rounded */}
              <SmartLink
                href={isHomePage ? "#planos" : "/#planos"}
                isAnchor={isHomePage}
                className="hidden xl:inline-flex px-5 py-2 border border-foreground/30 rounded-full text-[10px] uppercase tracking-[0.15em] text-foreground hover:border-accent hover:text-accent transition-colors"
              >
                {t('header.buySessions')}
              </SmartLink>

              {/* EXPERIMENTA JÁ — filled, rounded */}
              <SmartLink
                href={isHomePage ? "#try-now" : "/#try-now"}
                isAnchor={isHomePage}
                className="px-5 py-2 bg-foreground text-background rounded-full text-[10px] uppercase tracking-[0.15em] font-medium hover:bg-accent hover:text-accent-foreground transition-colors"
              >
                {t('header.tryNow')}
              </SmartLink>

              <LanguageSwitcher />
              <a href="https://strikershouse.yogobooking.pt/frontend/index.html#/my-profile" target="_blank" rel="noopener noreferrer" className="text-xs uppercase tracking-[0.12em] text-foreground/60 hover:text-foreground transition-colors">
                {t('header.myAccount')}
              </a>
            </div>

            {/* Mobile menu button */}
            <button
              className="lg:hidden text-foreground p-2"
              aria-label="Open menu"
              onClick={() => setIsMenuOpen(true)}
            >
              <Menu className="w-6 h-6" />
            </button>
          </nav>
        </div>

        {/* Gradient accent bar below header */}
        <div
          className="h-[2px] w-full"
          style={{ background: 'linear-gradient(90deg, hsl(0 72% 50%) 0%, hsl(0 72% 35%) 50%, hsl(0 0% 5%) 100%)' }}
        />
      </header>

      {/* Mobile Menu - Full Screen Overlay */}
      {isMenuOpen && (
        <div
          className="fixed inset-0 z-[9999] lg:hidden"
          style={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'hsl(0 0% 5%)',
            width: '100vw',
            height: '100vh'
          }}
        >
          {/* Close button */}
          <button
            className="absolute top-6 right-6 text-white p-2"
            aria-label="Close menu"
            onClick={() => setIsMenuOpen(false)}
          >
            <X className="w-6 h-6" />
          </button>

          {/* Menu Content */}
          <div className="flex flex-col items-center justify-center h-full px-6 overflow-y-auto">
            <nav className="flex flex-col items-center gap-7">
              {/* Experiência - expandable */}
              <div className="flex flex-col items-center">
                <button
                  onClick={() => setIsMobileExperienceOpen(!isMobileExperienceOpen)}
                  className="text-2xl tracking-[0.2em] uppercase font-light text-white/80 hover:text-white transition-colors flex items-center gap-2"
                >
                  {t('header.experience')}
                  <ChevronDown className={`w-5 h-5 transition-transform duration-200 ${isMobileExperienceOpen ? 'rotate-180' : ''}`} />
                </button>
                {isMobileExperienceOpen && (
                  <div className="mt-4 flex flex-col items-center gap-4">
                    {experienceItems.map((item) => (
                      <SmartLink
                        key={item.href}
                        href={item.href}
                        isAnchor={item.isAnchor}
                        onClick={handleLinkClick}
                        className="text-lg tracking-[0.15em] uppercase font-light text-white/50 hover:text-white transition-colors"
                      >
                        {item.label}
                      </SmartLink>
                    ))}
                  </div>
                )}
              </div>

              {/* Unidades */}
              <a
                href="#contact"
                onClick={handleLinkClick}
                className="text-2xl tracking-[0.2em] uppercase font-light text-white/80 hover:text-white transition-colors"
              >
                {t('header.locations')}
              </a>

              {/* Comunidade */}
              <Link
                to="/comunidade"
                onClick={handleLinkClick}
                className="text-2xl tracking-[0.2em] uppercase font-light text-white/80 hover:text-white transition-colors"
              >
                {t('header.community')}
              </Link>

              {/* Corporate */}
              <Link
                to="/corporate"
                onClick={handleLinkClick}
                className="text-2xl tracking-[0.2em] uppercase font-light text-white/80 hover:text-white transition-colors"
              >
                {t('header.corporate')}
              </Link>

              {/* CTAs */}
              <div className="mt-6 flex flex-col items-center gap-4">
                <SmartLink
                  href={isHomePage ? "#horario" : "/#horario"}
                  isAnchor={isHomePage}
                  onClick={handleLinkClick}
                  className="px-8 py-3 border border-white/30 rounded-full text-white text-xs uppercase tracking-[0.15em] hover:border-accent hover:text-accent transition-colors text-center w-64"
                >
                  {t('header.bookNow')}
                </SmartLink>
                <SmartLink
                  href={isHomePage ? "#planos" : "/#planos"}
                  isAnchor={isHomePage}
                  onClick={handleLinkClick}
                  className="px-8 py-3 border border-white/30 rounded-full text-white text-xs uppercase tracking-[0.15em] hover:border-accent hover:text-accent transition-colors text-center w-64"
                >
                  {t('header.buySessions')}
                </SmartLink>
                <SmartLink
                  href={isHomePage ? "#try-now" : "/#try-now"}
                  isAnchor={isHomePage}
                  onClick={handleLinkClick}
                  className="px-8 py-3 bg-white text-background rounded-full text-xs uppercase tracking-[0.15em] font-medium hover:bg-accent hover:text-accent-foreground transition-colors text-center w-64"
                >
                  {t('header.tryNow')}
                </SmartLink>
              </div>

              <div className="mt-6 flex flex-col items-center gap-5">
                <LanguageSwitcher />
                <a
                  href="https://strikershouse.yogobooking.pt/frontend/index.html#/my-profile"
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={handleLinkClick}
                  className="text-base tracking-[0.2em] uppercase font-light text-white/50 hover:text-white transition-colors"
                >
                  {t('header.myAccount')}
                </a>
              </div>
            </nav>
          </div>
        </div>
      )}
    </>
  );
};

export default Header;
