package debug;

import flixel.FlxG;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.system.System;
import openfl.display.Sprite;
import openfl.display.Shape;

/**
    The FPS class provides an easy-to-use monitor to display
    the current frame rate of an OpenFL project
**/
class FPSCounter extends Sprite
{
    public var currentFPS(default, null):Int;
    public var memoryMegas(get, never):Float;

    @:noCompletion private var times:Array<Float>;
    private var textField:TextField;
    private var background:Shape;

    public function new(x:Float = 10, y:Float = 10, color:Int = 0xFFFFFF)
    {
        super();

        this.x = x;
        this.y = y;

        currentFPS = 0;
        times = [];

        // Background
        background = new Shape();
        addChild(background);

        // Text field
        textField = new TextField();
        textField.defaultTextFormat = new TextFormat("_sans", 14, color);
        textField.selectable = false;
        textField.mouseEnabled = false;
        textField.multiline = true;
        textField.autoSize = LEFT;
        addChild(textField);
    }

    var deltaTimeout:Float = 0.0;

    private function updateBackground():Void
    {
        background.graphics.clear();
        background.graphics.beginFill(0x000000, 0.5); // semi-transparent black
        background.graphics.drawRect(0, 0, textField.width + 10, textField.height + 6);
        background.graphics.endFill();
    }

    private function updateText():Void
    {
        // Convert bytes -> MB
        var usedMemoryMB = Math.round(memoryMegas / (1024 * 1024));
        if (usedMemoryMB < 0) usedMemoryMB = 0;
        if (usedMemoryMB > 999) usedMemoryMB = 999; // clamp to 3 digits

        var totalMemoryMB = Math.round(System.totalMemory / (1024 * 1024));
        if (totalMemoryMB < 0) totalMemoryMB = 0;
        if (totalMemoryMB > 999) totalMemoryMB = 999;

        // Approximate RAM in GB (process memory, not real system RAM)
        var ramGB:Float = Math.round((totalMemoryMB / 1024.0) * 10) / 10;

        textField.text = "FPS " + currentFPS
                       + "\nMemory: " + usedMemoryMB + "mb (" + totalMemoryMB + "mb)"
                       + "\nRam: " + ramGB + "GB"
                       + "\nPsych Engine 1.0.4";

        updateBackground();
    }

    private override function __enterFrame(deltaTime:Float):Void
    {
        final now:Float = haxe.Timer.stamp() * 1000;
        times.push(now);
        while (times[0] < now - 1000) times.shift();

        if (deltaTimeout < 50) {
            deltaTimeout += deltaTime;
            return;
        }

        currentFPS = times.length < FlxG.updateFramerate ? times.length : FlxG.updateFramerate;        
        updateText();
        deltaTimeout = 0.0;
    }

    inline function get_memoryMegas():Float
        return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
}
