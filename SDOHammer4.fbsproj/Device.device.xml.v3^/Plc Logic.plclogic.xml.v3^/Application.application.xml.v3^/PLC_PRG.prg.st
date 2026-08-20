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
    aDataBuffs      : ARRAY[1..4] OF ARRAY[0..255] OF BYTE;
    aRandIndices    : ARRAY[1..4] OF WORD;
    aRandSubIndices : ARRAY[1..4] OF BYTE;
    aRandSizes      : ARRAY[1..4] OF CAA.SIZE;
	
    // Shared seed for the pseudo-random number generator
    dwRandSeed      : DWORD := 987654321;
    
    // Performance Metrics
    aReadCounts     : ARRAY[1..4] OF UDINT;
    aErrorCounts    : ARRAY[1..4] OF UDINT;
	aLastErrorCodes : ARRAY[1..4] OF ETC_CO_ERROR;
    aLastAbortCodes : ARRAY[1..4] OF DWORD;
    aReadStartTime  : ARRAY[1..4] OF SYSTIME;
    aReadEndTime    : ARRAY[1..4] OF SYSTIME;
    aElapsed        : ARRAY[1..4] OF ULINT;
	aTotalElapsed   : ARRAY[1..4] OF ULINT;
    aAverageTime    : ARRAY[1..4] OF REAL;

    // Iterator loop index
    i               : INT;
	
    // Pointer to traverse the sequential linked list
    pSlave          : POINTER TO ETCSlave;
	
	udiTargetIndex  : UDINT;
    
    bInitialized    : BOOL := FALSE;
	
	lastCycleTime   : SYSTIME;
	thisCycleTime   : SYSTIME;
	cycleTime       : SYSTIME;
	
END_VAR


IF NOT bInitialized THEN

	// wait for all slaves to be identified and linked into a list
	IF NOT EtherCAT_Master.xConfigFinished THEN
	    SlaveCount := 0;
		RETURN;
	END_IF
    
    // Fetch the entry point of the linked list from the Master node
    // Replace 'EtherCAT_Master' with the exact name of your master node
	IF 0 = pSlave THEN
		pSlave := EtherCAT_Master.FirstSlave;
	END_IF

	IF 0 = pSlave THEN
		// end of list, we're ready
		bInitialized := TRUE;
		RETURN;
	END_IF

	// wait for addresses to be assigned
	IF 0 = pSlave^.PhysSlaveAddr THEN
		RETURN;
	END_IF
	
	// got an address, advance to next one for next bus cycle
	SlaveCount := SlaveCount + 1;
	aSlaveIds[SlaveCount] := pSlave^.PhysSlaveAddr;
	IF 4 = SlaveCount THEN
		bInitialized := TRUE; // no more space, so start
	ELSE
		pSlave := pSlave^.NextInstance;
		RETURN;
	END_IF

END_IF

SysTimeGetUs(thisCycleTime);
cycleTime := thisCycleTime - lastCycleTime;
lastCycleTime := thisCycleTime;

// Loop through and evaluate all 4 state machines independently in the same PLC cycle
FOR i := 1 TO SlaveCount DO
    
    CASE aStates[i] OF
        0: // GENERATE PARAMETERS & PREPARE
            // Step the shared LCG pseudo-random generator
            dwRandSeed := (dwRandSeed * 1103515245 + 12345) MOD 16#7FFFFFFF;
            
			// Map the random value bounded strictly to your extracted ESI array length
			udiTargetIndex := TO_UDINT((dwRandSeed MOD TO_DWORD(GVL.MAX_VALID_SDOS)) + 1);

			// Pull valid paired parameters cleanly
			aRandIndices[i]    := GVL.aValidSDOs[udiTargetIndex].wIndex;
			aRandSubIndices[i] := GVL.aValidSDOs[udiTargetIndex].bySubIndex;
			aRandSizes[i]      := GVL.aValidSDOs[udiTargetIndex].szSize;
			
			// Reset the FB execute trigger
			aSdoReaders[i](xExecute := FALSE);
			SysTimeGetUs(aReadStartTime[i]);
			aStates[i] := 1;

        1: // TRIGGER & MONITOR READS IN PARALLEL
            aSdoReaders[i](
                xExecute    := TRUE,
                usiCom      := 1,
                uiDevice    := aSlaveIds[i],
                wIndex      := aRandIndices[i],
                bySubindex  := aRandSubIndices[i],
                pBuffer     := ADR(aDataBuffs[i]),
                szSize      := aRandSizes[i],
                udiTimeOut  := 10
            );
            
            IF aSdoReaders[i].xDone THEN
                aReadCounts[i] := aReadCounts[i] + 1;
				ComputeTime();
                aSdoReaders[i](xExecute := FALSE);
                aStates[i] := 0; // Instantly queue the next read
                
            ELSIF aSdoReaders[i].xError THEN
                aReadCounts[i] := aReadCounts[i] + 1;
				ComputeTime();
                aErrorCounts[i] := aErrorCounts[i] + 1;
				aLastErrorCodes[i] := aSdoReaders[i].eError;
                aLastAbortCodes[i] := aSdoReaders[i].udiSdoAbort;
                aSdoReaders[i](xExecute := FALSE);
                aStates[i] := 0; // Skip error and keep hammering
            END_IF
            
    END_CASE
    
END_FOR
END_PROGRAM