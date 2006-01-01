.586
.model flat, stdcall
option casemap:none

include windows.inc
include user32.inc
include kernel32.inc
include shell32.inc

includelib user32.lib
includelib kernel32.lib
includelib shell32.lib
include debug.inc
includelib debug.lib
WinMain proto :DWORD, :DWORD, :DWORD, :DWORD

.const

IDI_TRAY		=	0
WM_SHELLNOTIFY	=	WM_USER + 1
ID_TIMER		=	512

.data
	AppName db "Disk space monitor", 0
	ClassName db "MainWinClass", 0
	StaticClassName db "Static", 0

	Visible db 1 ; 1 if the main window is visible, 0 if not
	Format db "%s %d KB free", 0 ; display format
	Count dd 0 ; number of bytes received from GetLogicalDriveStrings
	Flags dd 16 dup (1) ; for each drive 1 if there is no error, 0 if there is an error

.data?
	hInstance HINSTANCE ?
	CommandLine LPSTR ?
	Info db 256 dup(?) ; strings received from GetLogicalDriveStrings
	Labels dd 16 dup (?) ; handles for the labels

.code

; ---------------------------------------------------------------------------

start:
	invoke GetModuleHandle, NULL
	mov hInstance, eax

	invoke GetCommandLine
	mov CommandLine, eax

	invoke WinMain, hInstance, NULL, CommandLine, SW_SHOWDEFAULT
	invoke ExitProcess, eax

WinMain proc hInst:HINSTANCE, hPrevInst:HINSTANCE, CmdLine:LPSTR, CmdShow:DWORD
	LOCAL wc : WNDCLASSEX
	LOCAL msg : MSG
	LOCAL hwnd : HWND

	mov wc.cbSize, sizeof WNDCLASSEX
	mov wc.style, CS_HREDRAW + CS_VREDRAW
	mov wc.lpfnWndProc, offset WndProc
	mov wc.cbClsExtra, NULL
	mov wc.cbWndExtra, NULL
	push  hInstance
	pop wc.hInstance
	mov wc.hbrBackground, COLOR_BTNFACE + 1
	mov wc.lpszMenuName, NULL
	mov wc.lpszClassName, offset ClassName

	invoke LoadIcon, NULL, IDI_APPLICATION
	mov wc.hIcon, eax
	mov wc.hIconSm, eax

	invoke LoadCursor, NULL, IDC_ARROW
	mov wc.hCursor, eax

	invoke RegisterClassEx, addr wc
	invoke CreateWindowEx, NULL, addr ClassName, addr AppName,
		WS_SYSMENU + WS_VISIBLE, 0, 0, 160, 0, HWND_DESKTOP, NULL,
		hInst, NULL
	mov hwnd, eax

	invoke ShowWindow, hwnd, SW_SHOWNORMAL
	invoke UpdateWindow, hwnd

	.while TRUE
		invoke GetMessage, addr msg, NULL, 0, 0
		.break .if (!eax)
		invoke TranslateMessage, addr msg
		invoke DispatchMessage, addr msg
	.endw

	mov eax, msg.wParam
	ret
WinMain endp

WndProc proc hWnd:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM
	LOCAL sectorsPerCluster : DWORD
	LOCAL bytesPerSector : DWORD
	LOCAL freeClusters : DWORD
	LOCAL totalClusters : DWORD
	LOCAL notifyIconData : NOTIFYICONDATA
	LOCAL hStatic : HWND ; handle to a label
	LOCAL message[64] : BYTE ; message to display
	LOCAL rect : RECT

	.if uMsg == WM_DESTROY

		invoke PostQuitMessage, NULL

	.elseif uMsg == WM_CREATE

		; prepare the tray icon
		mov eax, hWnd
		mov notifyIconData.cbSize, sizeof NOTIFYICONDATA
		mov notifyIconData.hwnd, eax
		mov notifyIconData.uID, IDI_TRAY
		mov notifyIconData.uFlags, NIF_ICON + NIF_MESSAGE + NIF_TIP
		mov notifyIconData.uCallbackMessage, WM_SHELLNOTIFY
		invoke lstrcpy, addr notifyIconData.szTip, addr AppName
		invoke LoadIcon, NULL, IDI_WINLOGO
		mov notifyIconData.hIcon, eax
		invoke Shell_NotifyIcon, NIM_ADD, addr notifyIconData

		; prepare the labels
		invoke GetLogicalDriveStrings, 255, addr Info
		mov Count, eax
		mov ecx, 0
		.while ecx != Count
			mov eax, ecx
			mov bl, 5
			mul bl

			push ecx
			invoke CreateWindowEx, WS_EX_CLIENTEDGE, addr StaticClassName, NULL,
				SS_LEFTNOWORDWRAP + WS_VISIBLE + WS_CHILD, 0, eax, 150, 20, hWnd, 0, hInstance, 0
			pop ecx
			mov [Labels + ecx], eax

			push ecx
			invoke GetWindowRect, hWnd, addr rect
			add rect.bottom, 20
			invoke SetWindowPos, hWnd, HWND_TOPMOST, rect.left, rect.top, rect.right, rect.bottom, NULL
			pop ecx

			add ecx, 4
		.endw

		; start the timer
		invoke SetTimer, hWnd, ID_TIMER, 1000, NULL

	.elseif uMsg == WM_SHELLNOTIFY ; systray click

		.if wParam == IDI_TRAY
			.if lParam == WM_LBUTTONDOWN
				.if Visible == 0
					invoke ShowWindow, hWnd, SW_SHOW
					mov Visible, 1
				.else
					invoke ShowWindow, hWnd, SW_HIDE
					mov Visible, 0
				.endif
			.endif
		.endif

	.elseif uMsg == WM_TIMER
PrintDec esp
		.if wParam == ID_TIMER
			mov ecx, 0
			.while ecx != Count
				mov eax, ecx
				mov esi, ecx
				.if [Flags + si] != 0 ; only handle this drive if it has no error
					push ecx
					invoke GetDiskFreeSpace, addr [Info + esi],
						addr sectorsPerCluster, addr bytesPerSector,
						addr freeClusters, addr totalClusters
					mov [Flags + esi], eax

					; compute the free bytes
					mov eax, freeClusters
					mul sectorsPerCluster
					mul bytesPerSector

					; compute the free kilobytes
					shr eax, 10

					; prepare the message
					push eax
					mov eax, offset Info
					add eax, esi
					push eax
					push offset Format
					lea eax, message
					push eax
					call wsprintf

					add sp, 16

					invoke SetWindowText, [esi + Labels], addr [message]
					pop ecx
				.endif
				add ecx, 4
			.endw
		.endif
	.else
		invoke DefWindowProc, hWnd, uMsg, wParam, lParam
		ret
	.endif

	xor eax, eax
	ret
WndProc endp

end start
