`timescale 1ns / 1ps
//============================================================================================
// Copyright: 
//   2026 DC Vision Systems GmbH
//============================================================================================
// Description:
//============================================================================================
// Authors:
//   David Madlener, Frederik Lange
//============================================================================================


module bfm_imager(
    input i_clk,
    input i_rst,
    output o_cam_pixel_clock,
    output o_cam_frame_valid,
    output o_cam_line_valid,
    output [11:0] o_cam_pixel_data
  );

  parameter lines_per_frame = 128;
  parameter pixels_per_line = 1280;
  parameter pixels_per_frame = lines_per_frame*pixels_per_line;
  parameter blank_pixels_per_line = 40;
  parameter blank_lines_per_frame = 8;
  parameter pixels_per_line_with_blank = pixels_per_line + blank_pixels_per_line;
  parameter lines_per_frame_with_blank = lines_per_frame + blank_lines_per_frame;
  parameter start_delay = 5000;
  parameter frame_delay = 10000;
  parameter line_delay = 10000;
  parameter S_IDLE = 2'd0;
  parameter S_TRANSFER_LINE = 2'd1;
  parameter S_BLANK_LINE = 2'd2;
  parameter S_BLANK_FRAME = 2'd3;
  parameter test_image0 = "./stimulus/raw0.hex";
  parameter test_image1 = "./stimulus/raw1.hex";
  parameter test_image2 = "./stimulus/raw4.hex";
  parameter test_image3 = "./stimulus/raw5.hex";
  parameter enable_test_pattern = 0;

  integer image_fd;
  integer scan_fd;
  integer check_fd;
  
  string test_image_name [0:3];     
  reg img_frame_valid;  
  reg img_line_valid;
  reg [31:0] frame_count;
  reg [11:0] pixel_data; 
  reg [15:0] line_count;
  reg [23:0] pixel_count;
  reg [15:0] blank_count;
  reg [15:0] pixel_value;
  reg [15:0] read_pixel; 
  reg [1:0] current_state;
  reg bit_toggle;
  reg internal_start;
  reg frame_delay_pending;
  time frame_restart_time;
    
  assign o_cam_pixel_clock = i_clk;
  assign o_cam_frame_valid = img_frame_valid;
  assign o_cam_line_valid = img_line_valid;
  assign o_cam_pixel_data = pixel_data;
  

  task change_test_image_name;
    input string new_name;
    input frame_number;
    begin
      if (enable_test_pattern == 0) begin
        check_fd = $fopen(new_name,"r");
        if (check_fd == 0) 
          begin
            $display(new_name," not found");
            $finish;
          end
        else begin
          $fclose(check_fd);
        end
      end

      test_image_name[frame_number] = new_name;
      $display("new image file ",test_image_name[frame_number]);
    end
  endtask

  task start_imager();
    internal_start = 1'b1;
  endtask

  task stop_imager();
    internal_start = 1'b0;
  endtask

  
  
  
  initial begin    
    //set file names for test images
    test_image_name[0] = test_image0;
    test_image_name[1] = test_image1;
    test_image_name[2] = test_image2;
    test_image_name[3] = test_image3;
    
    if (enable_test_pattern == 0) begin
      //open first image
      image_fd = $fopen(test_image_name[0],"r");
      if (image_fd == 0) 
        begin
          $display(test_image_name[0]," not found");
          $finish;
        end
      else
        $display("opened first image file %s",test_image_name[0]);
    end
    else begin
      image_fd = 0;
      $display("test pattern enabled: image files are not opened");
    end
  end
  
  
 
  
  // Reset assertion is asynchronous, including during the inter-frame pause.
  always @ (posedge i_clk or posedge i_rst)
  begin
    if (i_rst == 1) begin
      current_state   <= S_IDLE;
	    //image_fd        <= 0;
	    //scan_fd         <= 0;
      line_count      <= 0;
	    blank_count     <= 0;
      pixel_count     <= 0;
	    read_pixel      <= 0;
      pixel_value     <= 0;
      bit_toggle      <= 0;
      pixel_data      <= 0;
      img_frame_valid <= 0;
      img_line_valid  <= 0;
      frame_count     <= 0;
      internal_start  <= 0;
      frame_delay_pending <= 0;
      frame_restart_time <= 0;
    end
    else if (internal_start == 0) begin
      frame_delay_pending <= 0;
      current_state   <= S_IDLE;
      line_count      <= 0;
      blank_count     <= 0;
      pixel_count     <= 0;
      read_pixel      <= 0;
      pixel_value     <= 0;
      bit_toggle      <= 0;
      pixel_data      <= 0;
      img_frame_valid <= 0;
      img_line_valid  <= 0;
    end
    else if (frame_delay_pending) begin
      // Quantize the pause to i_clk without blocking reset events.
      if ($time >= frame_restart_time) begin
        frame_delay_pending <= 0;
        current_state <= S_IDLE;
        if (enable_test_pattern == 0) begin
          $fclose(image_fd);
          image_fd = $fopen(test_image_name[frame_count[1:0]],"r");
          $display("%s opened",test_image_name[frame_count[1:0]]);
        end
      end
    end
    else
      case (current_state)
        S_IDLE: begin
          if(internal_start == 1) begin
            current_state <= S_TRANSFER_LINE;
            line_count    <= 0;
            pixel_count   <= 0;
                  
            if (enable_test_pattern == 0) begin
              //read first pixel
              scan_fd = $fscanf(image_fd, "%h",read_pixel); 
              $display("%h",read_pixel);
              if ($feof(image_fd)) begin
                $display("end of image file reached before end of frame\n");
                $finish;
              end
              pixel_value <= read_pixel;
            end
            else begin
              // In test-pattern mode, no image file is read.
              // The pixel value is the pixel index within the current line.
              pixel_value <= 0;
            end

            bit_toggle <= 0;
            img_frame_valid <= 1; // start the frame     
            img_line_valid <= 0;              
          end
        end
        S_TRANSFER_LINE: begin
          img_line_valid <= 1;
          //if(bit_toggle == 0) begin
          //  bit_toggle <= 1;          

          //  pixel_data <= pixel_value[9:2];
          //end
          //else begin
            //bit_toggle <= 0;          

            //pixel_data[7:2] <= 0;
            //pixel_data[1:0] <= pixel_value[1:0];
            
          if (enable_test_pattern == 0) begin
            pixel_data <= pixel_value[11:0];
            scan_fd = $fscanf(image_fd, "%h",read_pixel);
            if (($feof(image_fd)) && (pixel_count<(pixels_per_frame-1))) begin
              $display("pixel count : %h %h",pixel_count, pixels_per_frame-1);
              $display("end of image file reached before end of frame\n");
              $finish;
            end
            pixel_value <= read_pixel;
          end
          else begin
            pixel_data <= (pixel_count % pixels_per_line);
            pixel_value <= 0;
          end
            
          pixel_count <= pixel_count + 1;
          if ((pixel_count % pixels_per_line) == pixels_per_line-1) begin
            current_state <=  S_BLANK_LINE;
            blank_count = 0;
          end                    
        end
        S_BLANK_LINE: begin
         img_line_valid <= 0;

          bit_toggle <= !bit_toggle;
          if (bit_toggle == 1) begin
            blank_count <= blank_count + 1;
            if (blank_count == blank_pixels_per_line-1) begin
              blank_count <= 0;
              line_count <= line_count + 1; 
              
              if (line_count == lines_per_frame-1) begin
               current_state <=  S_BLANK_FRAME;
               frame_count <= frame_count + 1;
              end
              else begin
               current_state <=  S_TRANSFER_LINE;              
               blank_count <= 0;               
              end
            end            
          end          
        end
        S_BLANK_FRAME: begin
          img_frame_valid <= 0;
        
          bit_toggle = !bit_toggle;
          if (bit_toggle == 1) begin
            blank_count <= blank_count + 1;
            if (blank_count == pixels_per_line_with_blank-1) begin
              blank_count <= 0;
              line_count <= line_count + 1; 
            
              if (line_count == lines_per_frame_with_blank-1) begin
                frame_delay_pending <= 1;
                frame_restart_time <= $time + frame_delay;
              end
            end
          end
      end
    endcase
  end
     
endmodule
