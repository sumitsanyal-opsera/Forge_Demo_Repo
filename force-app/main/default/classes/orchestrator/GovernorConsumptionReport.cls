/**
 * Immutable value object capturing per-scenario governor limit consumption
 * and budget comparison results.
 *
 * Instantiated by GovernorLimitBudget.getConsumptionReport() — callers do
 * not construct this directly except in unit tests.
 *
 * Exceeded flags use strict greater-than: soqlUsed > soqlBudget, which is
 * consistent with isWithinBudget() using <= comparison.
 */
global with sharing class GovernorConsumptionReport {

    global final Integer soqlUsed;
    global final Integer dmlUsed;
    global final Integer cpuUsed;
    global final Integer soqlBudget;
    global final Integer dmlBudget;
    global final Integer cpuBudget;
    global final Boolean soqlExceeded;
    global final Boolean dmlExceeded;
    global final Boolean cpuExceeded;

    global GovernorConsumptionReport(
        Integer soqlUsed,
        Integer dmlUsed,
        Integer cpuUsed,
        Integer soqlBudget,
        Integer dmlBudget,
        Integer cpuBudget
    ) {
        this.soqlUsed    = soqlUsed;
        this.dmlUsed     = dmlUsed;
        this.cpuUsed     = cpuUsed;
        this.soqlBudget  = soqlBudget;
        this.dmlBudget   = dmlBudget;
        this.cpuBudget   = cpuBudget;
        this.soqlExceeded = soqlUsed > soqlBudget;
        this.dmlExceeded  = dmlUsed  > dmlBudget;
        this.cpuExceeded  = cpuUsed  > cpuBudget;
    }
}
