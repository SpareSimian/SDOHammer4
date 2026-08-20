(* METADATA
{
	"v3Meta": {
		"objectGuid": "62b6cb8c-2b0a-4768-897c-8a0022aba963"
	}
}
*)
METHOD PRIVATE ComputeTime : BOOL
VAR_INPUT
END_VAR

SysTimeGetUs(aReadEndTime[i]);
aElapsed[i] := aReadEndTime[i] - aReadStartTime[i];
aTotalElapsed[i] := aTotalElapsed[i] + aElapsed[i];
aAverageTime[i] := TO_REAL(aTotalElapsed[i]) / TO_REAL(aReadCounts[i]);
END_METHOD