// ============================================================================
// home_defs.vh : shared codes for the FPGA Smart Home Controller
// (included inside module bodies)
// ============================================================================
// Command codes produced by cmd_parser
localparam [4:0] CMD_NONE    = 5'd0,
                 CMD_STATUS  = 5'd1,
                 CMD_MODE    = 5'd2,
                 CMD_FAN     = 5'd3,
                 CMD_LIGHT   = 5'd4,
                 CMD_TH      = 5'd5,
                 CMD_OCC     = 5'd6,
                 CMD_ARM     = 5'd7,
                 CMD_DISARM  = 5'd8,
                 CMD_PIN     = 5'd9,
                 CMD_ACK     = 5'd10,
                 CMD_TIME    = 5'd11,
                 CMD_FAST    = 5'd12,
                 CMD_ECO     = 5'd13,
                 CMD_PROFILE = 5'd14,
                 CMD_ENERGY  = 5'd15,
                 CMD_CLEAR   = 5'd16,
                 CMD_AI      = 5'd17,
                 CMD_ENV     = 5'd18;

// Response codes sent back over UART
localparam [2:0] RSP_NONE    = 3'd0,
                 RSP_OK      = 3'd1,
                 RSP_ERR     = 3'd2,
                 RSP_DENIED  = 3'd3,
                 RSP_LOCKED  = 3'd4,
                 RSP_STATUS  = 3'd5,
                 RSP_PROFILE = 3'd6,
                 RSP_ENERGY  = 3'd7;

// Security FSM states
localparam [2:0] SEC_DISARMED = 3'd0,
                 SEC_EXIT     = 3'd1,
                 SEC_ARMED    = 3'd2,
                 SEC_ENTRY    = 3'd3,
                 SEC_ALARM    = 3'd4;
