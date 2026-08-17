/*
 * Copyright (c) 2024 Uri Shaked
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_1DC_vga_dyoa (
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // IOs: Input path
  output wire [7:0] uio_out,  // IOs: Output path
  output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
  input  wire       ena,      // always 1 when the design is powered, so you can ignore it
  input  wire       clk,      // clock
  input  wire       rst_n     // reset_n - low to reset
);

  // VGA signals
  wire hsync;
  wire vsync;
  wire [1:0] R;
  wire [1:0] G;
  wire [1:0] B;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;

  // TinyVGA PMOD
  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

  // Unused outputs assigned to 0.
  assign uio_out = 0;
  assign uio_oe  = 0;

  // Suppress unused signals warning
  wire _unused_ok = &{ena, ui_in, uio_in};

  hvsync_generator hvsync_gen(
    .clk(clk),
    .reset(~rst_n),
    .hsync(hsync),
    .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x),
    .vpos(pix_y)
  );

  // ================================================================
  // Colors: 6-bit RGB = RR GG BB, 2 bits per channel
  // ================================================================
  wire [5:0] black  = 6'b000000;
  wire [5:0] yellow = 6'b111101;
  wire [5:0] white  = 6'b111111;
  wire [5:0] blue   = 6'b000011;
  wire [5:0] red    = 6'b110000;

  // Slow pulse used by all three text lines.
  reg [24:0] pulse_counter;

  always @(posedge clk) begin
    if (!rst_n)
      pulse_counter <= 25'd0;
    else
      pulse_counter <= pulse_counter + 1'b1;
  end

  wire pulse = ~pulse_counter[24];

  wire [5:0] blue_text  = pulse ? blue  : 6'b000001;
  wire [5:0] red_text   = pulse ? red   : 6'b010000;
  wire [5:0] white_text = pulse ? white : 6'b010101;

  // ================================================================
  // PIXEL STARS
  // The 8x8 ROM contains a single small dot. 
  // ================================================================
  function [7:0] star_rom;
    input [2:0] row;
    begin
      case (row)
        3'd0: star_rom = 8'b00000000;
        3'd1: star_rom = 8'b00010000;
        3'd2: star_rom = 8'b00000000;
        3'd3: star_rom = 8'b00000000;
        3'd4: star_rom = 8'b00000000;
        3'd5: star_rom = 8'b00000000;
        3'd6: star_rom = 8'b00000000;
        3'd7: star_rom = 8'b00000000;
      endcase
    end
  endfunction

  wire [7:0] star_row = star_rom(pix_y[2:0]);
  wire small_star = star_row[7 - pix_x[2:0]];

  // Pixel star placement

  wire [4:0] sx = pix_x[7:3];
  wire [4:0] sy = pix_y[7:3];

  wire sparse_tile =
      // upper background
      ((sx == 5'd3)  && (sy == 5'd3))  ||
      ((sx == 5'd10) && (sy == 5'd5))  ||
      ((sx == 5'd18) && (sy == 5'd3))  ||
      ((sx == 5'd25) && (sy == 5'd6))  ||
      ((sx == 5'd29) && (sy == 5'd2))  ||

      // middle background around the chip
      ((sx == 5'd3)  && (sy == 5'd25)) ||
      ((sx == 5'd8)  && (sy == 5'd28)) ||
      ((sx == 5'd14) && (sy == 5'd24)) ||
      ((sx == 5'd20) && (sy == 5'd27)) ||
      ((sx == 5'd27) && (sy == 5'd25)) ||

      ((sx == 5'd6)  && (sy == 5'd16)) ||
      ((sx == 5'd12) && (sy == 5'd20)) ||
      ((sx == 5'd21) && (sy == 5'd17)) ||
      ((sx == 5'd27) && (sy == 5'd21)) ||

      // lower background
      ((sx == 5'd3)  && (sy == 5'd40)) ||
      ((sx == 5'd10) && (sy == 5'd43)) ||
      ((sx == 5'd18) && (sy == 5'd41)) ||
      ((sx == 5'd25) && (sy == 5'd44)) ||
      ((sx == 5'd29) && (sy == 5'd39));

  wire stars =
      video_active &&
      (pix_y > 10'd100) &&
      (pix_y < 10'd420) &&
      small_star &&
      sparse_tile;

  // ================================================================
  // Three lines of "DESIGN YOUR OWN ASIC" text
  // 5x7 font, enlarged by 3x:
  //   character width = 15 pixels
  //   character spacing = 3 pixels
  //   cell width = 18 pixels
  //
  // 20 characters -> 360 pixels total.
  // Centered: (640 - 360)/2 = 140.
  // ================================================================

  wire text_x_active =
      (pix_x >= 10'd140) && (pix_x < 10'd500);

  wire line_blue =
      (pix_y >= 10'd20) && (pix_y < 10'd41);

  wire line_red =
      (pix_y >= 10'd48) && (pix_y < 10'd69);

  wire line_white =
      (pix_y >= 10'd76) && (pix_y < 10'd97);

  wire text_active =
      text_x_active && (line_blue || line_red || line_white);

  // Position inside the text.
  wire [9:0] text_x = pix_x - 10'd140;
  wire [9:0] text_y =
      line_blue  ? (pix_y - 10'd20) :
      line_red   ? (pix_y - 10'd48) :
                   (pix_y - 10'd76);

  // Character number = floor(text_x / 18).
  // For text_x = 0..359, floor(x/18) == floor(x*57/1024).
  // 57 = 32 + 16 + 8 + 1, so this is shift/add logic.
  wire [15:0] char_mul57 =
      (text_x << 5) + (text_x << 4) + (text_x << 3) + text_x;
  wire [5:0] char_index = char_mul57[15:10];

  // Character pixel position inside the 18-pixel character cell.
  // 18*char_index = 16*char_index + 2*char_index.
  wire [9:0] char_start =
      (char_index << 4) + (char_index << 1);
  wire [4:0] char_x = text_x - char_start;

  // Character row = floor(text_y / 3).
  // For text_y = 0..20, floor(y/3) == floor(y*43/128).
  // 43 = 32 + 8 + 2 + 1.
  wire [14:0] char_mul43 =
      (text_y << 5) + (text_y << 3) + (text_y << 1) + text_y;
  wire [4:0] char_y = char_mul43[14:7];

  // First 15 pixels of each 18-pixel cell are the 5x7 glyph.
  wire text_inside_char =
      text_active &&
      (char_x < 5'd15) &&
      (char_y < 5'd7);

  // 5x7 font
  function [4:0] glyph_row;
    input [5:0] c;
    input [2:0] row;
    begin
      case (c)

        // D
        6'd0: case(row)
          0: glyph_row=5'b11110;
          1: glyph_row=5'b10001;
          2: glyph_row=5'b10001;
          3: glyph_row=5'b10001;
          4: glyph_row=5'b10001;
          5: glyph_row=5'b10001;
          6: glyph_row=5'b11110;
        endcase

        // E
        6'd1: case(row)
          0: glyph_row=5'b11111;
          1: glyph_row=5'b10000;
          2: glyph_row=5'b10000;
          3: glyph_row=5'b11110;
          4: glyph_row=5'b10000;
          5: glyph_row=5'b10000;
          6: glyph_row=5'b11111;
        endcase

        // S
        6'd2: case(row)
          0: glyph_row=5'b01111;
          1: glyph_row=5'b10000;
          2: glyph_row=5'b10000;
          3: glyph_row=5'b01110;
          4: glyph_row=5'b00001;
          5: glyph_row=5'b00001;
          6: glyph_row=5'b11110;
        endcase

        // I
        6'd3: case(row)
          0: glyph_row=5'b11111;
          1: glyph_row=5'b00100;
          2: glyph_row=5'b00100;
          3: glyph_row=5'b00100;
          4: glyph_row=5'b00100;
          5: glyph_row=5'b00100;
          6: glyph_row=5'b11111;
        endcase

        // G
        6'd4: case(row)
          0: glyph_row=5'b01111;
          1: glyph_row=5'b10000;
          2: glyph_row=5'b10000;
          3: glyph_row=5'b10111;
          4: glyph_row=5'b10001;
          5: glyph_row=5'b10001;
          6: glyph_row=5'b01111;
        endcase

        // N
        6'd5: case(row)
          0: glyph_row=5'b10001;
          1: glyph_row=5'b11001;
          2: glyph_row=5'b10101;
          3: glyph_row=5'b10011;
          4: glyph_row=5'b10001;
          5: glyph_row=5'b10001;
          6: glyph_row=5'b10001;
        endcase

        // SPACE
        6'd6: glyph_row=5'b00000;

        // Y
        6'd7: case(row)
          0: glyph_row=5'b10001;
          1: glyph_row=5'b10001;
          2: glyph_row=5'b01010;
          3: glyph_row=5'b00100;
          4: glyph_row=5'b00100;
          5: glyph_row=5'b00100;
          6: glyph_row=5'b00100;
        endcase

        // O
        6'd8: case(row)
          0: glyph_row=5'b01110;
          1: glyph_row=5'b10001;
          2: glyph_row=5'b10001;
          3: glyph_row=5'b10001;
          4: glyph_row=5'b10001;
          5: glyph_row=5'b10001;
          6: glyph_row=5'b01110;
        endcase

        // U
        6'd9: case(row)
          0: glyph_row=5'b10001;
          1: glyph_row=5'b10001;
          2: glyph_row=5'b10001;
          3: glyph_row=5'b10001;
          4: glyph_row=5'b10001;
          5: glyph_row=5'b10001;
          6: glyph_row=5'b01110;
        endcase

        // R
        6'd10: case(row)
          0: glyph_row=5'b11110;
          1: glyph_row=5'b10001;
          2: glyph_row=5'b10001;
          3: glyph_row=5'b11110;
          4: glyph_row=5'b10100;
          5: glyph_row=5'b10010;
          6: glyph_row=5'b10001;
        endcase

        // W
        6'd11: case(row)
          0: glyph_row=5'b10001;
          1: glyph_row=5'b10001;
          2: glyph_row=5'b10001;
          3: glyph_row=5'b10101;
          4: glyph_row=5'b10101;
          5: glyph_row=5'b11011;
          6: glyph_row=5'b10001;
        endcase

        // A
        6'd12: case(row)
          0: glyph_row=5'b01110;
          1: glyph_row=5'b10001;
          2: glyph_row=5'b10001;
          3: glyph_row=5'b11111;
          4: glyph_row=5'b10001;
          5: glyph_row=5'b10001;
          6: glyph_row=5'b10001;
        endcase

        // C
        6'd13: case(row)
          0: glyph_row=5'b01111;
          1: glyph_row=5'b10000;
          2: glyph_row=5'b10000;
          3: glyph_row=5'b10000;
          4: glyph_row=5'b10000;
          5: glyph_row=5'b10000;
          6: glyph_row=5'b01111;
        endcase

        default: glyph_row=5'b00000;
      endcase
    end
  endfunction

  // Convert the character number into phrase.
  // DESIGN YOUR OWN ASIC
  function [5:0] phrase_char;
    input [5:0] n;
    begin
      case(n)
        0:  phrase_char=0;   // D
        1:  phrase_char=1;   // E
        2:  phrase_char=2;   // S
        3:  phrase_char=3;   // I
        4:  phrase_char=4;   // G
        5:  phrase_char=5;   // N
        6:  phrase_char=6;   // space
        7:  phrase_char=7;   // Y
        8:  phrase_char=8;   // O
        9:  phrase_char=9;   // U
        10: phrase_char=10;  // R
        11: phrase_char=6;   // space
        12: phrase_char=8;   // O
        13: phrase_char=11;  // W
        14: phrase_char=5;   // N
        15: phrase_char=6;   // space
        16: phrase_char=12;  // A
        17: phrase_char=2;   // S
        18: phrase_char=3;   // I
        19: phrase_char=13;  // C
        default: phrase_char=6;
      endcase
    end
  endfunction

  wire [5:0] current_char = phrase_char(char_index);

  // Select one of the five glyph columns.
  // char_x is 0..14, with each glyph pixel enlarged 3x.
  // floor(x/3) == floor(x*43/128) for x=0..14.
  wire [9:0] glyph_mul43 =
      (char_x << 5) + (char_x << 3) + (char_x << 1) + char_x;
  wire [2:0] glyph_col = glyph_mul43[9:7];

  wire [4:0] glyph_bits =
      glyph_row(current_char, char_y[2:0]);

  wire text_pixel =
      text_inside_char &&
      glyph_bits[4 - glyph_col];

  // ================================================================
  // CHIP SYMBOL
  // ================================================================
  // Chip body: 128 x 128
  // Left = 256, Top = 176
  // ================================================================

  wire chip =
      (pix_x >= 10'd256) && (pix_x < 10'd384) &&
      (pix_y >= 10'd176) && (pix_y < 10'd304);

  // Chip boundary
  wire chip_bl =
      (pix_x >= 10'd246) && (pix_x < 10'd251) &&
      (pix_y >= 10'd166) && (pix_y < 10'd314);

  wire chip_br =
      (pix_x >= 10'd389) && (pix_x < 10'd394) &&
      (pix_y >= 10'd166) && (pix_y < 10'd314);

  wire chip_bt =
      (pix_x >= 10'd246) && (pix_x < 10'd394) &&
      (pix_y >= 10'd166) && (pix_y < 10'd171);

  wire chip_bb =
      (pix_x >= 10'd246) && (pix_x < 10'd394) &&
      (pix_y >= 10'd309) && (pix_y < 10'd314);

  // Pins left/right
  wire pin_side_x =
      ((pix_x >= 10'd226) && (pix_x < 10'd246)) ||
      ((pix_x >= 10'd394) && (pix_x < 10'd414));

  wire pin_y =
      ((pix_y >= 10'd177) && (pix_y < 10'd184)) ||
      ((pix_y >= 10'd194) && (pix_y < 10'd201)) ||
      ((pix_y >= 10'd211) && (pix_y < 10'd218)) ||
      ((pix_y >= 10'd228) && (pix_y < 10'd235)) ||
      ((pix_y >= 10'd245) && (pix_y < 10'd252)) ||
      ((pix_y >= 10'd262) && (pix_y < 269)) ||
      ((pix_y >= 10'd279) && (pix_y < 286)) ||
      ((pix_y >= 10'd296) && (pix_y < 303));

  wire chip_pins_lr = pin_side_x && pin_y;

  // Pins top/bottom
  wire pin_topbottom_y =
      ((pix_y >= 10'd314) && (pix_y < 10'd334)) ||
      ((pix_y >= 10'd146) && (pix_y < 10'd166));

  wire pin_x =
      ((pix_x >= 10'd257) && (pix_x < 10'd264)) ||
      ((pix_x >= 10'd274) && (pix_x < 281)) ||
      ((pix_x >= 10'd291) && (pix_x < 298)) ||
      ((pix_x >= 10'd308) && (pix_x < 315)) ||
      ((pix_x >= 10'd325) && (pix_x < 332)) ||
      ((pix_x >= 10'd342) && (pix_x < 349)) ||
      ((pix_x >= 10'd359) && (pix_x < 366)) ||
      ((pix_x >= 10'd376) && (pix_x < 383));

  wire chip_pins_tb = pin_topbottom_y && pin_x;

  wire chip_pixel =
      chip || chip_bl || chip_br || chip_bt || chip_bb ||
      chip_pins_lr || chip_pins_tb;

  // ================================================================
  // RGB PRIORITY
  // 1. Chip      = yellow
  // 2. Text      = blue / red / white
  // 3. Stars     = white
  // 4. Background = black
  // ================================================================
  wire [5:0] text_color =
      line_blue  ? blue_text  :
      line_red   ? red_text   :
                   white_text;

  assign R = video_active ?
             (chip_pixel ? yellow[5:4] :
              text_pixel ? text_color[5:4] :
              stars      ? white[5:4] :
              black[5:4]) : 2'b00;

  assign G = video_active ?
             (chip_pixel ? yellow[3:2] :
              text_pixel ? text_color[3:2] :
              stars      ? white[3:2] :
              black[3:2]) : 2'b00;

  assign B = video_active ?
             (chip_pixel ? yellow[1:0] :
              text_pixel ? text_color[1:0] :
              stars      ? white[1:0] :
              black[1:0]) : 2'b00;

endmodule

`default_nettype wire