package com.hashicorp.vaultdynamicsecrets.constants;

/**
 * API-wide constants (pagination bounds, etc.). Not instantiable.
 */
public final class ApiConstants {

    private ApiConstants() {
    }

    /** Default page index when the client does not specify one. */
    public static final String DEFAULT_PAGE = "0";

    /** Default page size when the client does not specify one. */
    public static final String DEFAULT_SIZE = "20";

    /** Hard cap so a client can never request an unbounded result set. */
    public static final int MAX_PAGE_SIZE = 100;

    /** Smallest page size we will honour. */
    public static final int MIN_PAGE_SIZE = 1;
}
