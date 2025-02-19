import { css, cx } from "@emotion/css";
import { useTheme } from "@emotion/react";
import Badge from "@mui/material/Badge";
import type { WorkspaceBuild } from "api/typesGenerated";
import { BuildIcon } from "components/BuildIcon/BuildIcon";
import { Avatar, type AvatarProps } from "components/deprecated/Avatar/Avatar";
import { useClassName } from "hooks/useClassName";
import type { FC } from "react";
import { getDisplayWorkspaceBuildStatus } from "utils/workspace";

export interface BuildAvatarProps {
	build: WorkspaceBuild;
	size?: AvatarProps["size"];
}

export const BuildAvatar: FC<BuildAvatarProps> = ({ build, size }) => {
	const theme = useTheme();
	const { status, type } = getDisplayWorkspaceBuildStatus(theme, build);
	const badgeType = useClassName(
		(css, theme) => css({ backgroundColor: theme.roles[type].fill.solid }),
		[type],
	);

	return (
		<Badge
			role="status"
			aria-label={status}
			title={status}
			overlap="circular"
			anchorOrigin={{ vertical: "bottom", horizontal: "right" }}
			badgeContent={<div></div>}
			classes={{ badge: cx(classNames.badge, badgeType) }}
		>
			<Avatar background size={size}>
				<BuildIcon transition={build.transition} />
			</Avatar>
		</Badge>
	);
};

const classNames = {
	badge: css({
		borderRadius: "100%",
		width: 8,
		minWidth: 8,
		height: 8,
		display: "block",
		padding: 0,
	}),
};
