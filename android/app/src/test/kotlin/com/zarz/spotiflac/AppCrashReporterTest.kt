package com.zarz.spotiflac

import android.app.ApplicationExitInfo
import org.json.JSONObject
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
    fun includesCrashesAndAnr() {
        for (reason in listOf(
            ApplicationExitInfo.REASON_CRASH,
            ApplicationExitInfo.REASON_CRASH_NATIVE,
            ApplicationExitInfo.REASON_ANR,
        )) {
            assertTrue(AppCrashReporter.isUnexpectedExit(reason))
        }
    }

    @Test
    fun normalExitsForceStopsAndUpdatesAreNotReportedAsCrashes() {
        for (reason in listOf(
            ApplicationExitInfo.REASON_LOW_MEMORY,
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE,
            ApplicationExitInfo.REASON_SIGNALED,
            ApplicationExitInfo.REASON_EXIT_SELF,
            ApplicationExitInfo.REASON_USER_REQUESTED,
            ApplicationExitInfo.REASON_USER_STOPPED,
            ApplicationExitInfo.REASON_PACKAGE_UPDATED,
            ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE,
        )) {
            assertFalse(AppCrashReporter.isUnexpectedExit(reason))
        }
    }

    @Test
    fun osKillSignalsAreIgnoredWhileFatalSignalsRemainReported() {
        for (signal in listOf(0, 9, 15)) {
            assertFalse(AppCrashReporter.isUnexpectedExit(ApplicationExitInfo.REASON_SIGNALED, signal))
        }
        for (signal in listOf(4, 5, 6, 7, 8, 11, 31)) {
            assertTrue(AppCrashReporter.isUnexpectedExit(ApplicationExitInfo.REASON_SIGNALED, signal))
        }
    }

    @Test
    fun oldSavedSystemKillsAreHiddenButActualCrashReportsRemainVisible() {
        for (reason in listOf(ApplicationExitInfo.REASON_LOW_MEMORY, ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE)) {
            assertFalse(AppCrashReporter.shouldShowSavedReport(JSONObject().put("reason_code", reason)))
        }
        assertFalse(AppCrashReporter.shouldShowSavedReport(JSONObject()
            .put("reason_code", ApplicationExitInfo.REASON_SIGNALED).put("status", 9)))
        assertTrue(AppCrashReporter.shouldShowSavedReport(JSONObject()
            .put("reason_code", ApplicationExitInfo.REASON_CRASH_NATIVE)))
        assertTrue(AppCrashReporter.shouldShowSavedReport(JSONObject()
            .put("reason", "Unhandled Android exception").put("trace", "java.lang.OutOfMemoryError")))
    }
}
