package com.zarz.spotiflac

import android.app.ApplicationExitInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppCrashReporterTest {
    @Test
    fun aSecondStartupCrashCannotBeOverwrittenByPreviousExitRecovery() {
        assertTrue(AppCrashReporter.shouldKeepSavedReport(2250L, 2000L, 2200L))
        assertFalse(AppCrashReporter.shouldKeepSavedReport(1950L, 2000L, 2200L))
    }

    @Test
    fun includesCrashesAnrAndOsResourceKills() {
        for (reason in listOf(
            ApplicationExitInfo.REASON_CRASH,
            ApplicationExitInfo.REASON_CRASH_NATIVE,
            ApplicationExitInfo.REASON_ANR,
            ApplicationExitInfo.REASON_LOW_MEMORY,
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE,
            ApplicationExitInfo.REASON_SIGNALED,
        )) {
            assertTrue(AppCrashReporter.isUnexpectedExit(reason))
        }
    }

    @Test
    fun normalExitsForceStopsAndUpdatesAreNotReportedAsCrashes() {
        for (reason in listOf(
            ApplicationExitInfo.REASON_EXIT_SELF,
            ApplicationExitInfo.REASON_USER_REQUESTED,
            ApplicationExitInfo.REASON_USER_STOPPED,
            ApplicationExitInfo.REASON_PACKAGE_UPDATED,
            ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE,
        )) {
            assertFalse(AppCrashReporter.isUnexpectedExit(reason))
        }
    }
}
