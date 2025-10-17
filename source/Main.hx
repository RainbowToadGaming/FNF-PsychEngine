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
import haxe.io.Path;
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

        #if (cpp && windows)
        backend.Native.fixScaling();
        #end

        #if android
        Sys.setCwd(Path.addTrailingSlash(Context.getExternalFilesDir()));
        #elseif ios
        Sys.setCwd(lime.system.System.applicationStorageDirectory);
        #end

        #if VIDEOS_ALLOWED
        hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0") ['--no-lua'] #end);
        #end

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
        // ZERO-LAG OPTIMIZATIONS
        // -------------------------

        FlxG.fixedTimestep = true;           // Fixed update loop
        FlxG.maxElapsed = 1 / 60;            // Avoid big delta spikes
        Lib.current.stage.frameRate = 60;    // Lock display framerate
        FlxG.game.focusLostFramerate = 60;  
        FlxG.autoPause = false;              // Don't pause on focus lost
        FlxG.keys.preventDefaultKeys = [TAB];

        FlxG.drawFramerate = 0; // skip FPS display in intensive scenarios

        // Disable filters/shaders per camera (optional but boosts FPS)
        FlxG.signals.gameResized.add(resetSpriteCacheAll);

        addChild(new FlxGame(
            game.width,
            game.height,
            game.initialState,
            60, // update rate
            60, // draw rate
            game.skipSplash,
            game.startFullscreen
        ));

        #if !mobile
        fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
        addChild(fpsVar);
        Lib.current.stage.align = "tl";
        Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
        if(fpsVar != null) fpsVar.visible = ClientPrefs.data.showFPS;
        #end

        #if (linux || mac)
        var icon = Image.fromFile("icon.png");
        Lib.current.stage.window.setIcon(icon);
        #end

        #if html5
        FlxG.mouse.visible = false;
        #end

        #if CRASH_HANDLER
        Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
        #end

        #if DISCORD_ALLOWED
        DiscordClient.prepare();
        #end
    }

    static function resetSpriteCache(sprite:Sprite):Void {
        @:privateAccess {
            sprite.__cacheBitmap = null;
            sprite.__cacheBitmapData = null;
        }
    }

    static function resetSpriteCacheAll(w:Int, h:Int):Void {
        if (FlxG.cameras != null) {
            for (cam in FlxG.cameras.list) {
                if (cam != null && cam.filters != null)
                    resetSpriteCache(cam.flashSprite);
            }
        }
        if (FlxG.game != null) resetSpriteCache(FlxG.game);
    }

    #if HSCRIPT_ALLOWED
    static function setupIrisLogging():Void {
        Iris.warn = logWarning;
        Iris.error = logError;
        Iris.fatal = logFatal;
    }

    static function logWarning(x:String, ?pos:haxe.PosInfos):Void {
        Iris.logLevel(WARN, x, pos);
        if (PlayState.instance != null) PlayState.instance.addTextToDebug('WARNING: $x', 0xFFFF00);
    }

    static function logError(x:String, ?pos:haxe.PosInfos):Void {
        Iris.logLevel(ERROR, x, pos);
        if (PlayState.instance != null) PlayState.instance.addTextToDebug('ERROR: $x', 0xFF0000);
    }

    static function logFatal(x:String, ?pos:haxe.PosInfos):Void {
        Iris.logLevel(FATAL, x, pos);
        if (PlayState.instance != null) PlayState.instance.addTextToDebug('FATAL: $x', 0xFFBB0000);
    }
    #end

    #if CRASH_HANDLER
    static function onCrash(e:UncaughtErrorEvent):Void
    {
        var errMsg:String = "";
        var callStack:Array<StackItem> = CallStack.exceptionStack(true);
        var dateNow:String = Date.now().toString().replace(" ", "_").replace(":", "'");

        var path = "./crash/PsychEngine_" + dateNow + ".txt";
        for (stackItem in callStack) switch (stackItem) {
            case FilePos(s, file, line, column): errMsg += file + " (line " + line + ")\n";
            default: Sys.println(stackItem);
        }

        errMsg += "\nUncaught Error: " + e.error;
        #if officialBuild
        errMsg += "\nPlease report this error: https://github.com/ShadowMario/FNF-PsychEngine";
        #end
        errMsg += "\n\n> Crash Handler by sqirra-rng";

        if (!FileSystem.exists("./crash/")) FileSystem.createDirectory("./crash/");
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
