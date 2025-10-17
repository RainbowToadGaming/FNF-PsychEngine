package;

#if android
import android.content.Context;
#end

import debug.FPSCounter;

import flixel.FlxGame;
import flixel.FlxG;
import flixel.FlxState;
import haxe.io.Path;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.display.StageScaleMode;
import lime.app.Application;
import states.TitleState;

#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
import psychlua.HScript.HScriptInfos;
#end

#if (linux || mac)
import lime.graphics.Image;
#end

#if desktop
import backend.ALSoftConfig;
#end

#if CRASH_HANDLER
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
#end

import backend.Highscore;

#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end

class Main extends Sprite
{
    public static final game = {
        width: 1280,
        height: 720,
        initialState: TitleState,
        framerate: 60,
        skipSplash: true,
        startFullscreen: false
    };

    public static var fpsVar:FPSCounter;

    public static function main():Void
    {
        Lib.current.addChild(new Main());
    }

    public function new()
    {
        super();

        // Fix scaling for Windows builds
        #if (cpp && windows)
        backend.Native.fixScaling();
        #end

        // Set working directory for Android / iOS
        #if android
        Sys.setCwd(Path.addTrailingSlash(Context.getExternalFilesDir()));
        #elseif ios
        Sys.setCwd(lime.system.System.applicationStorageDirectory);
        #end

        // Initialize video handler (if allowed)
        #if VIDEOS_ALLOWED
        hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0") ['--no-lua'] #end);
        #end

        // Load mods and preferences
        #if LUA_ALLOWED
        Mods.pushGlobalMods();
        #end
        Mods.loadTopMod();

        FlxG.save.bind('funkin', CoolUtil.getSavePath());
        Highscore.load();

        #if HSCRIPT_ALLOWED
        setupIrisLogging();
        #end

        #if LUA_ALLOWED
        Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call));
        #end

        Controls.instance = new Controls();
        ClientPrefs.loadDefaultKeys();

        #if ACHIEVEMENTS_ALLOWED
        Achievements.load();
        #end

        // -------------------------
        // GAME INITIALIZATION
        // -------------------------
        var gameInstance = new FlxGame(
            game.width,
            game.height,
            game.initialState,
            60, // update rate
            60, // draw rate
            game.skipSplash,
            game.startFullscreen
        );
        addChild(gameInstance);

        // Setup FPS counter safely
        #if !mobile
        fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
        addChild(fpsVar);
        Lib.current.stage.align = "tl";
        Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;

        if (fpsVar != null && ClientPrefs.data != null)
            fpsVar.visible = ClientPrefs.data.showFPS;
        #end

        // Set stage icon (Linux/Mac only)
        #if (linux || mac)
        var icon = Image.fromFile("icon.png");
        Lib.current.stage.window.setIcon(icon);
        #end

        // Hide mouse on HTML5 builds
        #if html5
        FlxG.mouse.visible = false;
        #end

        // Crash handler
        #if CRASH_HANDLER
        Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(
            UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash
        );
        #end

        // Discord RPC init
        #if DISCORD_ALLOWED
        DiscordClient.prepare();
        #end

        // -------------------------
        // DELAYED INITIALIZATION (Safe FlxG access)
        // -------------------------
        Application.current.onEnter.add(function() {
            if (FlxG != null && FlxG.game != null) {
                FlxG.fixedTimestep = true;
                FlxG.maxElapsed = 1 / 60;
                FlxG.autoPause = false;
                FlxG.keys.preventDefaultKeys = [TAB];
                FlxG.drawFramerate = 0;

                // Safe signals + cache reset
                if (FlxG.signals != null)
                    FlxG.signals.gameResized.add(resetSpriteCacheAll);

                Lib.current.stage.frameRate = 60;
                FlxG.game.focusLostFramerate = 60;
            }
        });
    }

    // -------------------------
    // Sprite cache handling
    // -------------------------
    static function resetSpriteCache(sprite:Sprite):Void {
        if (sprite == null) return;
        @:privateAccess {
            sprite.__cacheBitmap = null;
            sprite.__cacheBitmapData = null;
        }
    }

    static function resetSpriteCacheAll(w:Int, h:Int):Void {
        if (FlxG == null) return;

        if (FlxG.cameras != null && FlxG.cameras.list != null) {
            for (cam in FlxG.cameras.list) {
                if (cam != null && cam.flashSprite != null)
                    resetSpriteCache(cam.flashSprite);
            }
        }

        if (FlxG.game != null)
            resetSpriteCache(FlxG.game);
    }

    // -------------------------
    // HScript / Iris logging
    // -------------------------
    #if HSCRIPT_ALLOWED
    static function setupIrisLogging():Void {
        Iris.warn = logWarning;
        Iris.error = logError;
        Iris.fatal = logFatal;
    }

    static function logWarning(x:String, ?pos:haxe.PosInfos):Void {
        if (PlayState.instance != null)
            PlayState.instance.addTextToDebug('WARNING: $x', 0xFFFF00);
    }

    static function logError(x:String, ?pos:haxe.PosInfos):Void {
        if (PlayState.instance != null)
            PlayState.instance.addTextToDebug('ERROR: $x', 0xFF0000);
    }

    static function logFatal(x:String, ?pos:haxe.PosInfos):Void {
        if (PlayState.instance != null)
            PlayState.instance.addTextToDebug('FATAL: $x', 0xFFBB0000);
    }
    #end

    // -------------------------
    // Crash handler
    // -------------------------
    #if CRASH_HANDLER
    static function onCrash(e:UncaughtErrorEvent):Void
    {
        var errMsg:String = "";
        var callStack:Array<StackItem> = CallStack.exceptionStack(true);
        var dateNow:String = Date.now().toString().replace(" ", "_").replace(":", "'");
        var path = "./crash/PsychEngine_" + dateNow + ".txt";

        for (stackItem in callStack)
            switch (stackItem) {
                case FilePos(_, file, line, _):
                    errMsg += file + " (line " + line + ")\n";
                default:
            }

        errMsg += "\nUncaught Error: " + e.error;
        #if officialBuild
        errMsg += "\nPlease report this error: https://github.com/ShadowMario/FNF-PsychEngine";
        #end
        errMsg += "\n\n> Crash Handler by sqirra-rng";

        if (!FileSystem.exists("./crash/"))
            FileSystem.createDirectory("./crash/");
        File.saveContent(path, errMsg + "\n");

        Sys.println(errMsg);
        Sys.println("Crash dump saved in " + Path.normalize(path));

        Application.current.window.alert(errMsg, "Error!");
        #if DISCORD_ALLOWED
        DiscordClient.shutdown();
        #end
        Sys.exit(1);
    }
    #end
}
