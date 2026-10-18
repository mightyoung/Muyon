package com.mightyoung.muyon.ocr;

import java.lang.instrument.Instrumentation;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;
import java.util.concurrent.CancellationException;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.agent.ByteBuddyAgent;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.loading.ClassReloadingStrategy;
import org.opencv.core.Mat;
import org.opencv.core.Core;
import org.opencv.imgproc.Imgproc;
import static net.bytebuddy.matcher.ElementMatchers.*;

/** Test-only observation of real JNI Mats; no native calls or allocations are mocked. */
public final class NativeMatTracker {
    public static final Set<Mat> allocated = Collections.newSetFromMap(new IdentityHashMap<>());
    public static final Set<Mat> released = Collections.newSetFromMap(new IdentityHashMap<>());
    public static String cancelAt;
    public static boolean active;
    public static int maximumLiveAtExtraction;
    public static int nonChannelAtExtraction;
    private static boolean installed;

    public static void install() {
        if (installed) return;
        Instrumentation instrumentation = ByteBuddyAgent.install();
        ClassReloadingStrategy strategy = ClassReloadingStrategy.of(instrumentation);
        new ByteBuddy().redefine(Mat.class)
            .visit(Advice.to(Allocated.class).on(isConstructor()))
            .visit(Advice.to(Released.class).on(named("release")))
            .visit(Advice.to(Cancel.class).on(named("convertTo")))
            .visit(Advice.to(Extract.class).on(named("get").and(takesArguments(int.class, int.class, float[].class))))
            .make().load(Mat.class.getClassLoader(), strategy);
        new ByteBuddy().redefine(Imgproc.class)
            .visit(Advice.to(Cancel.class).on(named("warpPerspective").or(named("cvtColor"))))
            .make().load(Imgproc.class.getClassLoader(), strategy);
        new ByteBuddy().redefine(Core.class)
            .visit(Advice.to(Cancel.class).on(named("rotate").or(named("split"))))
            .make().load(Core.class.getClassLoader(), strategy);
        installed = true;
    }

    public static void start(String cancellation) {
        allocated.clear(); released.clear(); cancelAt = cancellation;
        maximumLiveAtExtraction = 0; nonChannelAtExtraction = 0; active = true;
    }
    public static void stop() { active = false; cancelAt = null; }
    public static class Allocated {
        @Advice.OnMethodExit public static void exit(@Advice.This Mat mat) {
            if (active) allocated.add(mat);
        }
    }
    public static class Released {
        @Advice.OnMethodEnter public static void enter(@Advice.This Mat mat) {
            if (active) released.add(mat);
        }
    }
    public static class Extract {
        @Advice.OnMethodEnter public static void enter() {
            if (!active) return;
            int live = 0;
            for (Mat mat : allocated) {
                if (!released.contains(mat)) {
                    live++;
                    if (mat.channels() != 1 || mat.depth() != org.opencv.core.CvType.CV_32F) nonChannelAtExtraction++;
                }
            }
            maximumLiveAtExtraction = Math.max(maximumLiveAtExtraction, live);
        }
    }
    public static class Cancel {
        @Advice.OnMethodEnter public static void enter(@Advice.Origin("#m") String method) {
            if (active && method.equals(cancelAt)) throw new CancellationException("injected cancellation at " + method);
        }
    }
}
