(* METADATA
{
	"v3Meta": {
		"objectGuid": "265bd9e0-f119-4664-b8ae-ea3439835427"
	}
}
*)
PROGRAM PLC_PRG
VAR
    // Array of independent function blocks for parallel execution
    aSdoReaders     : ARRAY[1..4] OF ETC_CO_SdoRead;
    
    // Independent states for each slave's execution loop
    aStates         : ARRAY[1..4] OF INT := [4(0)];
    
    // Configuration for 4 slaves (Populate with actual Node IDs from your device tree)
    aSlaveIds       : ARRAY[1..4] OF UINT;
    SlaveCount      : INT := 0;
	
    // Unique data buffers and random parameters per slave pipeline
    aDataBuffs      : ARRAY[1..4] OF ARRAY[0..3] OF BYTE;
    aRandIndices    : ARRAY[1..4] OF WORD;
    aRandSubIndices : ARRAY[1..4] OF BYTE;
    
    // Shared seed for the pseudo-random number generator
    dwRandSeed      : DWORD := 987654321;
    
    // Performance Metrics
    aReadCounts     : ARRAY[1..4] OF UDINT;
    aErrorCounts    : ARRAY[1..4] OF UDINT;
    aLastAbortCodes : ARRAY[1..4] OF DWORD;
    
    // Iterator loop index
    i               : INT;
	
    // Pointer to traverse the sequential linked list
    pSlave          : POINTER TO ETCSlave;
	
	udiTargetIndex  : UDINT;
    
    bInitialized    : BOOL := FALSE;
	
END_VAR


IF NOT bInitialized THEN
    SlaveCount := 0;
    
    // Fetch the entry point of the linked list from the Master node
    // Replace 'EtherCAT_Master' with the exact name of your master node
    pSlave := EtherCAT_Master.FirstSlave;
    
    // Loop through the hardware nodes sequentially until a null pointer or index 4 is hit
    WHILE pSlave <> 0 AND SlaveCount < 4 DO
        SlaveCount := SlaveCount + 1;
        
        // Capture the internal hardware address required by ETC_CO_SdoRead
        aSlaveIds[SlaveCount] := pSlave^.PhysSlaveAddr; 
        
        // Advance seamlessly to the next slave object down the physical line
        pSlave := pSlave^.NextInstance;
    END_WHILE
    
    bInitialized := TRUE;
END_IF

// Loop through and evaluate all 4 state machines independently in the same PLC cycle
FOR i := 1 TO 4 DO
    
    CASE aStates[i] OF
        0: // GENERATE PARAMETERS & PREPARE
            // Step the shared LCG pseudo-random generator
            dwRandSeed := (dwRandSeed * 1103515245 + 12345) MOD 16#7FFFFFFF;
            
			// Map the random value bounded strictly to your extracted ESI array length
			udiTargetIndex := TO_UDINT((dwRandSeed MOD TO_DWORD(GVL.MAX_VALID_SDOS)) + 1);

			// Pull valid paired parameters cleanly
			aRandIndices[i]    := GVL.aValidSDOs[udiTargetIndex].wIndex;
			aRandSubIndices[i] := GVL.aValidSDOs[udiTargetIndex].bySubIndex;

            // Reset the FB execute trigger
            aSdoReaders[i](xExecute := FALSE);
            aStates[i] := 1;

        1: // TRIGGER & MONITOR READS IN PARALLEL
            aSdoReaders[i](
                xExecute    := TRUE,
                usiCom      := 1,
                uiDevice    := aSlaveIds[i],
                wIndex      := aRandIndices[i],
                bySubindex  := aRandSubIndices[i],
                pBuffer     := ADR(aDataBuffs[i]),
                szSize     := SIZEOF(aDataBuffs[i]),
                udiTimeOut  := 50 // Fast 50ms timeout
            );
            
            IF aSdoReaders[i].xDone THEN
                aReadCounts[i] := aReadCounts[i] + 1;
                aSdoReaders[i](xExecute := FALSE);
                aStates[i] := 0; // Instantly queue the next read
                
            ELSIF aSdoReaders[i].xError THEN
                aErrorCounts[i] := aErrorCounts[i] + 1;
                aLastAbortCodes[i] := aSdoReaders[i].udiSdoAbort;
                aSdoReaders[i](xExecute := FALSE);
                aStates[i] := 0; // Skip error and keep hammering
            END_IF
            
    END_CASE
    
END_FOR
END_PROGRAM