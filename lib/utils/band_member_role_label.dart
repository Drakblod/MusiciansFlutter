/// Formats a band membership role at the point of display.
String bandMemberRoleLabel(String? role) {
  if (role?.trim().toLowerCase() == 'leader') return 'Bandleader';
  return role ?? 'Member';
}
