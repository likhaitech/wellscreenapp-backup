package com.wellscreen.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceAdminAlertRetryJobServiceTest {

    private val hour = 60L * 60L * 1000L

    @Test
    fun retriesWhenPendingAlertIsRecent() {
        assertTrue(DeviceAdminAlertRetryPolicy.shouldRetry(1000L, 1000L + hour))
    }

    @Test
    fun retriesBeforeTwentyFourHourExpiry() {
        assertTrue(DeviceAdminAlertRetryPolicy.shouldRetry(1000L, 1000L + 23L * hour))
    }

    @Test
    fun doesNotRetryWithoutSavedAlert() {
        assertFalse(DeviceAdminAlertRetryPolicy.shouldRetry(0L, 1000L))
    }

    @Test
    fun doesNotRetryAtTwentyFourHourExpiry() {
        assertFalse(DeviceAdminAlertRetryPolicy.shouldRetry(1000L, 1000L + 24L * hour))
    }

    @Test
    fun doesNotRetryFutureTimestamp() {
        assertFalse(DeviceAdminAlertRetryPolicy.shouldRetry(2000L, 1000L))
    }

    @Test
    fun clearsMatchingAlertAfterSuccess() {
        assertTrue(DeviceAdminAlertRetryPolicy.shouldClear(1000L, 1000L, true))
    }

    @Test
    fun preservesAlertAfterFailure() {
        assertFalse(DeviceAdminAlertRetryPolicy.shouldClear(1000L, 1000L, false))
    }

    @Test
    fun preservesNewerAlertWhenOlderDeliverySucceeds() {
        assertFalse(DeviceAdminAlertRetryPolicy.shouldClear(2000L, 1000L, true))
    }
}
