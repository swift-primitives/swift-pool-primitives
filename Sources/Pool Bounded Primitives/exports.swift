// exports.swift
// Pool Bounded Primitives module exports.

@_exported public import Pool_Primitive
@_exported public import Pool_Scope_Primitives
@_exported public import Pool_ID_Primitives
@_exported public import Pool_Error_Primitives
@_exported public import Pool_Capacity_Primitives
@_exported public import Pool_Lifecycle_Primitives
@_exported public import Pool_Metrics_Primitives

// External foundations used module-wide by Bounded's implementation files
// (restores the module-wide visibility the former Core target re-exported).
@_exported public import Async_Primitives
@_exported public import Dimension_Primitives
@_exported public import Ownership_Primitives
