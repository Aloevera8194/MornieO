package com.zarz.spotiflac

import android.app.Application

class SpotiFlacApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppCrashReporter.initialize(this)
    }
}
