package lt.hereader.server.catalogue;

/// Whether every step of `CatalogueRefresh.runAll()` succeeded. Deliberately
/// one flag, not one per step — no caller of `CatalogueRefresh` needs to
/// distinguish which half failed, only whether the whole sweep did.
record CatalogueRefreshOutcome(boolean succeeded) {}
