type BrandVariant = 'light' | 'dark' | 'compact'
const logos = {
  light: '/brand/ruel-concrete-light.jpg',
  dark: '/brand/ruel-concrete-dark.png',
  compact: '/brand/ruel-concrete-compact.gif',
}
export default function Brand({ label, variant = 'light' }: { label: string; variant?: BrandVariant }) {
  return <div className={`brand brand--${variant}`} aria-label={`RUEL Concrete · ${label}`}>
    <img className="brand-logo" src={logos[variant]} alt="RUEL Concrete" decoding="async" />
    <span className="brand-label">{label}</span>
  </div>
}
