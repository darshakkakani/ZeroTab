declare module 'xirr' {
  interface XirrCashflow {
    amount: number;
    when: Date;
  }

  export default function xirr(cashflows: XirrCashflow[]): number;
}
