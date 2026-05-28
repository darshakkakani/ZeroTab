const MERCHANT_CATEGORY_MAP: Record<string, string> = {
  zomato: "food_delivery", swiggy: "food_delivery", dunzo: "food_delivery",
  blinkit: "food_delivery", zepto: "food_delivery", instamart: "food_delivery",
  ola: "transport", uber: "transport", rapido: "transport", metro: "transport",
  irctc: "transport", auto: "transport", rickshaw: "transport",
  bpcl: "fuel", "indian oil": "fuel", iocl: "fuel", hp: "fuel", shell: "fuel",
  bescom: "utilities", airtel: "utilities", jio: "utilities", bsnl: "utilities",
  netflix: "subscriptions", spotify: "subscriptions", "amazon prime": "subscriptions",
  hotstar: "subscriptions", disney: "subscriptions", youtube: "subscriptions",
  "big bazaar": "grocery", dmart: "grocery", bigbasket: "grocery", jiomart: "grocery",
  amazon: "shopping", flipkart: "shopping", myntra: "shopping", meesho: "shopping",
  nykaa: "shopping", ajio: "shopping",
  pvr: "entertainment", inox: "entertainment", bookmyshow: "entertainment",
  apollo: "health", medplus: "health", "1mg": "health", pharmeasy: "health",
  lic: "insurance", "hdfc life": "insurance", "max life": "insurance",
  sip: "investment", groww: "investment", zerodha: "investment", upstox: "investment",
  starbucks: "food_delivery", dominos: "food_delivery", kfc: "food_delivery",
  decathlon: "shopping", lenskart: "health",
};

export function autoCategory(merchant: string): string {
  const m = merchant.toLowerCase();
  for (const [keyword, cat] of Object.entries(MERCHANT_CATEGORY_MAP)) {
    if (m.includes(keyword)) return cat;
  }
  return "others";
}
